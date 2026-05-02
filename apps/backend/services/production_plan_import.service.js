/**
 * apps/backend/services/production_plan_import.service.js
 * -------------------------------------------------------
 * WHAT:
 * - Extracts usable planning text from uploaded draft source documents.
 *
 * WHY:
 * - Frontend-only PDF scraping misses compressed ReportLab streams and causes
 *   AI draft generation to see only a thin fragment of the source plan.
 *
 * HOW:
 * - Normalizes uploaded metadata, decodes base64 file bytes, extracts text from
 *   txt/html/pdf sources, and returns a task-density estimate for prompt use.
 */

const zlib = require("zlib");

const MAX_SOURCE_DOCUMENT_BYTES = 4 * 1024 * 1024;
const MAX_SOURCE_DOCUMENT_TEXT_CHARS = 120000;
const SHORT_MONTH_INDEX = {
  jan: 0,
  feb: 1,
  mar: 2,
  apr: 3,
  may: 4,
  jun: 5,
  jul: 6,
  aug: 7,
  sep: 8,
  oct: 9,
  nov: 10,
  dec: 11,
};

function parseString(value) {
  return value == null ? "" : value.toString().trim();
}

function normalizeExtension(fileName, extension) {
  const explicit = parseString(extension).toLowerCase();
  if (explicit) {
    return explicit;
  }
  const trimmed = parseString(fileName).toLowerCase();
  const parts = trimmed.split(".");
  return parts.length > 1 ? parts.pop().trim() : "";
}

function normalizeImportedDocumentText(rawText) {
  const cleaned = (rawText || "")
    .toString()
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, " ")
    .replace(/[ \t]+/g, " ");
  const lines = cleaned
    .split(/[\r\n]+/)
    .map((line) => line.trim())
    .filter(Boolean);
  return lines.join("\n");
}

function stripHtmlTags(rawHtml) {
  return (rawHtml || "")
    .toString()
    .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, " ")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

function decodeAscii85(input) {
  const text = (input || "")
    .toString()
    .replace(/\s+/g, "")
    .replace(/^<~/, "")
    .replace(/~>$/, "");
  const output = [];
  let tuple = [];

  function pushTuple(values, bytesToEmit) {
    let value = 0;
    for (const digit of values) {
      value = value * 85 + digit;
    }
    const chunk = [
      (value >>> 24) & 0xff,
      (value >>> 16) & 0xff,
      (value >>> 8) & 0xff,
      value & 0xff,
    ];
    output.push(...chunk.slice(0, bytesToEmit));
  }

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (!char) {
      continue;
    }
    if (char === "z" && tuple.length === 0) {
      output.push(0, 0, 0, 0);
      continue;
    }
    const code = char.charCodeAt(0);
    if (code < 33 || code > 117) {
      continue;
    }
    tuple.push(code - 33);
    if (tuple.length === 5) {
      pushTuple(tuple, 4);
      tuple = [];
    }
  }

  if (tuple.length > 0) {
    const originalLength = tuple.length;
    while (tuple.length < 5) {
      tuple.push(84);
    }
    pushTuple(tuple, originalLength - 1);
  }

  return Buffer.from(output);
}

function decodePdfLiteralString(rawFragment) {
  const text = (rawFragment || "").toString();
  let output = "";

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (char !== "\\") {
      output += char;
      continue;
    }

    index += 1;
    if (index >= text.length) {
      break;
    }

    const escaped = text[index];
    if (escaped === "n") {
      output += "\n";
      continue;
    }
    if (escaped === "r") {
      output += "\r";
      continue;
    }
    if (escaped === "t") {
      output += "\t";
      continue;
    }
    if (escaped === "b") {
      output += "\b";
      continue;
    }
    if (escaped === "f") {
      output += "\f";
      continue;
    }
    if (escaped === "(" || escaped === ")" || escaped === "\\") {
      output += escaped;
      continue;
    }
    if (escaped === "\n") {
      continue;
    }
    if (escaped === "\r") {
      if (text[index + 1] === "\n") {
        index += 1;
      }
      continue;
    }
    if (/[0-7]/.test(escaped)) {
      let octal = escaped;
      while (
        octal.length < 3 &&
        /[0-7]/.test(text[index + 1] || "")
      ) {
        index += 1;
        octal += text[index];
      }
      output += String.fromCharCode(parseInt(octal, 8));
      continue;
    }

    output += escaped;
  }

  return output;
}

function decodePdfHexString(rawFragment) {
  const cleaned = (rawFragment || "").toString().replace(/\s+/g, "");
  if (!cleaned) {
    return "";
  }
  const padded =
    cleaned.length % 2 === 0 ? cleaned : `${cleaned}0`;
  try {
    return Buffer.from(padded, "hex").toString("latin1");
  } catch (_) {
    return "";
  }
}

function extractTextOperatorsFromPdfContent(content) {
  const text = (content || "").toString("latin1");
  const collected = [];

  function collectFragment(fragment, decoder = decodePdfLiteralString) {
    const decoded = normalizeImportedDocumentText(decoder(fragment)).trim();
    if (!decoded || decoded.length < 2) {
      return;
    }
    collected.push(decoded);
  }

  const literalPatterns = [
    /\(((?:\\.|[^\\()])*)\)\s*Tj/g,
    /\(((?:\\.|[^\\()])*)\)\s*'/g,
    /\(((?:\\.|[^\\()])*)\)\s*"/g,
  ];
  for (const pattern of literalPatterns) {
    for (const match of text.matchAll(pattern)) {
      const fragment = match[1];
      if (fragment != null) {
        collectFragment(fragment);
      }
    }
  }

  for (const match of text.matchAll(/\[(.*?)\]\s*TJ/gs)) {
    const arrayText = match[1] || "";
    for (const inner of arrayText.matchAll(/\(((?:\\.|[^\\()])*)\)/g)) {
      if (inner[1] != null) {
        collectFragment(inner[1]);
      }
    }
    for (const inner of arrayText.matchAll(/<([0-9A-Fa-f\s]+)>/g)) {
      if (inner[1] != null) {
        collectFragment(inner[1], decodePdfHexString);
      }
    }
  }

  for (const match of text.matchAll(/<([0-9A-Fa-f\s]+)>\s*Tj/g)) {
    if (match[1] != null) {
      collectFragment(match[1], decodePdfHexString);
    }
  }

  if (collected.length > 0) {
    return collected.join("\n");
  }

  const printableRuns = text.match(/[A-Za-z][A-Za-z0-9 ,.;:()/_\-]{24,}/g);
  return printableRuns ? printableRuns.join("\n") : "";
}

function extractTextFromPdfBuffer(buffer) {
  const raw = Buffer.isBuffer(buffer)
    ? buffer.toString("latin1")
    : Buffer.from(buffer || []).toString("latin1");
  const collected = [];

  for (const objectMatch of raw.matchAll(/(\d+\s+\d+\s+obj[\s\S]*?endobj)/g)) {
    const objectText = objectMatch[1] || "";
    if (!objectText.includes("stream")) {
      continue;
    }
    const streamMatch = objectText.match(/stream[\r\n]+([\s\S]*?)endstream/);
    if (!streamMatch) {
      continue;
    }

    let streamData = streamMatch[1] || "";
    streamData = streamData.replace(/^\r?\n/, "").replace(/\r?\n$/, "");
    let decodedBuffer = Buffer.from(streamData, "latin1");

    try {
      if (objectText.includes("/ASCII85Decode")) {
        decodedBuffer = decodeAscii85(streamData);
      }
      if (objectText.includes("/FlateDecode")) {
        try {
          decodedBuffer = zlib.inflateSync(decodedBuffer);
        } catch (_) {
          decodedBuffer = zlib.inflateRawSync(decodedBuffer);
        }
      }
    } catch (_) {
      continue;
    }

    const extracted = extractTextOperatorsFromPdfContent(decodedBuffer);
    if (extracted.trim()) {
      collected.push(extracted.trim());
    }
  }

  if (collected.length > 0) {
    return collected.join("\n");
  }

  const printableRuns = raw.match(/[A-Za-z][A-Za-z0-9 ,.;:()/_\-]{24,}/g);
  return printableRuns ? printableRuns.join("\n") : "";
}

function estimateTaskLikeLineCount(rawText) {
  const lines = normalizeImportedDocumentText(rawText)
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
  const taskLinePattern =
    /\b(task|activity|operation|monitor|inspect|apply|transplant|plant|seed|seedling|harvest|spray|prune|scout|irrigat|fertigat|weed|pest|disease|pack|grade|record|clean|trellis|stake)\b/i;
  const bulletPattern = /^(\d+[\).:-]|[-*•])\s+/;
  const dayPattern = /^(day|week)\s*\d+/i;

  return lines.filter((line) => {
    const normalized = line.toLowerCase();
    if (normalized.length < 6 || normalized.length > 180) {
      return false;
    }
    if (
      /^(page|title|estate|crop|start date|end date|notes|manager notes|last saved|project days|tasks|phase allocation)/i.test(
        normalized,
      )
    ) {
      return false;
    }
    return (
      bulletPattern.test(line) ||
      dayPattern.test(normalized) ||
      taskLinePattern.test(normalized)
    );
  }).length;
}

function extractTextFromSourceDocumentBuffer({
  extension,
  buffer,
}) {
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) {
    return "";
  }
  switch (extension) {
    case "html":
    case "htm":
      return normalizeImportedDocumentText(
        stripHtmlTags(buffer.toString("utf8")),
      );
    case "txt":
      return normalizeImportedDocumentText(
        buffer.toString("utf8"),
      );
    case "pdf":
      return normalizeImportedDocumentText(
        extractTextFromPdfBuffer(buffer),
      );
    default:
      return normalizeImportedDocumentText(
        buffer.toString("utf8"),
      );
  }
}

function extractAiDraftSourceDocumentContext(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    return null;
  }

  const fileName = parseString(input.fileName);
  const extension = normalizeExtension(fileName, input.extension);
  const contentBase64 = parseString(input.contentBase64);
  const frontendExtractedText = normalizeImportedDocumentText(
    input.frontendExtractedText || "",
  );
  if (!contentBase64 && !frontendExtractedText) {
    return null;
  }

  let buffer = Buffer.alloc(0);
  if (contentBase64) {
    try {
      buffer = Buffer.from(contentBase64, "base64");
    } catch (_) {
      buffer = Buffer.alloc(0);
    }
  }
  if (buffer.length > MAX_SOURCE_DOCUMENT_BYTES) {
    buffer = buffer.subarray(0, MAX_SOURCE_DOCUMENT_BYTES);
  }

  const extractedFromBuffer = extractTextFromSourceDocumentBuffer({
    extension,
    buffer,
  });
  const resolvedText =
    extractedFromBuffer.trim() || frontendExtractedText.trim();
  if (!resolvedText) {
    return null;
  }

  const normalizedText = normalizeImportedDocumentText(resolvedText);
  const truncatedText =
    normalizedText.length <= MAX_SOURCE_DOCUMENT_TEXT_CHARS
      ? normalizedText
      : `${normalizedText.slice(0, MAX_SOURCE_DOCUMENT_TEXT_CHARS)}\n...[source document truncated]`;

  return {
    fileName,
    extension,
    text: truncatedText,
    byteLength: buffer.length,
    taskLineEstimate: estimateTaskLikeLineCount(truncatedText),
  };
}

function normalizeImportedSentence(value) {
  return parseString(value)
    .replace(/[–—−]/g, "-")
    .replace(/\s+/g, " ")
    .trim();
}

function formatIsoDate(value) {
  if (!(value instanceof Date) || Number.isNaN(value.getTime())) {
    return "";
  }
  return value.toISOString().slice(0, 10);
}

function parseShortMonthDate(value, fallbackYear) {
  const normalized = normalizeImportedSentence(value);
  const match =
    normalized.match(
      /^(\d{1,2})\s+([A-Za-z]{3,})(?:\s+(\d{4}))?$/,
    );
  if (!match) {
    return null;
  }

  const day = Number(match[1]);
  const monthKey = match[2].slice(0, 3).toLowerCase();
  const monthIndex = SHORT_MONTH_INDEX[monthKey];
  const year = Number(match[3] || fallbackYear || 0);
  if (
    !Number.isFinite(day) ||
    day < 1 ||
    day > 31 ||
    !Number.isFinite(monthIndex) ||
    !Number.isFinite(year) ||
    year < 1900
  ) {
    return null;
  }

  return new Date(Date.UTC(year, monthIndex, day, 0, 0, 0, 0));
}

function parseLongDateRange(value) {
  const normalized = normalizeImportedSentence(value);
  const match =
    normalized.match(
      /^(\d{1,2}\s+[A-Za-z]{3}\s+\d{4})\s+to\s+(\d{1,2}\s+[A-Za-z]{3}\s+\d{4})(?:\s+(\d+)\s+day\(s\))?$/i,
    );
  if (!match) {
    return null;
  }

  const startDate = parseShortMonthDate(match[1]);
  const endDate = parseShortMonthDate(match[2]);
  if (!startDate || !endDate) {
    return null;
  }

  return {
    startDate,
    endDate,
    dayCount: Number(match[3] || 0) || 0,
  };
}

function isImportedPageHeaderLine(value) {
  return /^Page\s+\d+$/i.test(normalizeImportedSentence(value));
}

function isImportedPhaseHeaderLine(value) {
  return /^Phase\s+\d+\s*:/i.test(normalizeImportedSentence(value));
}

function isImportedTaskBoundaryLine(value) {
  return /^Day\s+\d+$/i.test(normalizeImportedSentence(value));
}

function isImportedTableHeaderLine(value) {
  return /^(Project Day|Date|Task|Detail)$/i.test(
    normalizeImportedSentence(value),
  );
}

function extractImportedDocumentTitle(lines) {
  return (
    lines.find(
      (line) =>
        /production plan/i.test(line) &&
        !/^Phase\s+\d+/i.test(line),
    ) || ""
  );
}

function extractImportedCorrectionNotes(lines) {
  const startIndex = lines.findIndex((line) =>
    /^Correction Notes$/i.test(normalizeImportedSentence(line)),
  );
  if (startIndex < 0) {
    return "";
  }

  const collected = [];
  for (let index = startIndex + 1; index < lines.length; index += 1) {
    const line = lines[index];
    if (isImportedPhaseHeaderLine(line)) {
      break;
    }
    if (isImportedPageHeaderLine(line) || isImportedTableHeaderLine(line)) {
      continue;
    }
    const normalized = normalizeImportedSentence(line)
      .replace(/^[-*•]+\s*/, "")
      .trim();
    if (normalized) {
      collected.push(normalized);
    }
  }

  return collected.join(" ").trim();
}

function extractImportedGreenhouseCount(lines) {
  for (const line of lines) {
    const normalized = normalizeImportedSentence(line);
    const match = normalized.match(/(\d[\d,]*)\s+greenhouses?/i);
    if (match) {
      const parsed = Number(
        match[1].replace(/,/g, ""),
      );
      if (Number.isFinite(parsed) && parsed > 0) {
        return Math.floor(parsed);
      }
    }
  }
  return 0;
}

function extractImportedPlantingTargets(lines, fallbackTargets = {}) {
  let plannedPlantingQuantity = Number(
    fallbackTargets?.plannedPlantingQuantity || 0,
  );
  let plannedPlantingUnit = parseString(
    fallbackTargets?.plannedPlantingUnit,
  );
  let materialType = parseString(
    fallbackTargets?.materialType,
  );
  let estimatedHarvestQuantity = Number(
    fallbackTargets?.estimatedHarvestQuantity || 0,
  );
  let estimatedHarvestUnit = parseString(
    fallbackTargets?.estimatedHarvestUnit,
  );

  for (let index = 0; index < lines.length; index += 1) {
    const normalized = normalizeImportedSentence(lines[index]);
    const nextLine = normalizeImportedSentence(lines[index + 1] || "");
    const plantingBasisMatch = normalized.match(
      /(\d[\d,]*)\s+plants?\s+per\s+greenhouse.*\((\d[\d,]*)\s+total\s+planned\s+plants?\)/i,
    );
    if (plantingBasisMatch) {
      const totalPlants = Number(
        plantingBasisMatch[2].replace(/,/g, ""),
      );
      if (Number.isFinite(totalPlants) && totalPlants > 0) {
        plannedPlantingQuantity = totalPlants;
        plannedPlantingUnit = "plant";
        materialType = materialType || "seedling";
      }
    }

    const estimatedHarvestMatch = normalized.match(
      /(\d[\d,]*)\s*(kg|g|ton|bags?|sacks?|crates?|cartons?|baskets?|boxes?|buckets?|stands?)\s+(?:estimated\s+)?harvest/i,
    );
    const estimatedHarvestValueMatch =
      /^Estimated Harvest$/i.test(normalized) ?
        nextLine.match(
          /^(\d[\d,]*)\s*(kg|g|ton|bags?|sacks?|crates?|cartons?|baskets?|boxes?|buckets?|stands?)$/i,
        )
      : null;
    const resolvedHarvestMatch =
      estimatedHarvestMatch ||
      estimatedHarvestValueMatch;
    if (resolvedHarvestMatch) {
      const parsedQuantity = Number(
        resolvedHarvestMatch[1].replace(/,/g, ""),
      );
      if (Number.isFinite(parsedQuantity) && parsedQuantity > 0) {
        estimatedHarvestQuantity = parsedQuantity;
        estimatedHarvestUnit = resolvedHarvestMatch[2]
          .toLowerCase()
          .replace(/s$/, "");
      }
    }
  }

  return {
    materialType: materialType || "seedling",
    plannedPlantingQuantity:
      Number.isFinite(plannedPlantingQuantity) &&
        plannedPlantingQuantity > 0
      ? plannedPlantingQuantity
      : null,
    plannedPlantingUnit:
      plannedPlantingUnit || "plant",
    estimatedHarvestQuantity:
      Number.isFinite(estimatedHarvestQuantity) &&
        estimatedHarvestQuantity > 0
      ? estimatedHarvestQuantity
      : null,
    estimatedHarvestUnit:
      estimatedHarvestUnit || "",
  };
}

function splitImportedTaskTitleAndDetail(lines) {
  const collected = lines
    .map((line) => normalizeImportedSentence(line))
    .filter(Boolean);
  if (collected.length === 0) {
    return {
      title: "Imported task",
      detail: "Imported from uploaded source document.",
    };
  }
  if (collected.length === 1) {
    return {
      title: collected[0],
      detail: "Imported from uploaded source document.",
    };
  }

  let detailStartIndex = 1;
  const secondLine = collected[1] || "";
  const shouldTreatSecondLineAsTitleContinuation =
    collected.length > 2 &&
    !/[.!?]$/.test(secondLine) &&
    secondLine.split(/\s+/).length <= 6 &&
    collected[0].length <= 48;
  if (shouldTreatSecondLineAsTitleContinuation) {
    detailStartIndex = 2;
  }

  const title = collected
    .slice(0, detailStartIndex)
    .join(" ")
    .trim();
  const detail = collected
    .slice(detailStartIndex)
    .join(" ")
    .trim();

  return {
    title: title || "Imported task",
    detail: detail || "Imported from uploaded source document.",
  };
}

function inferImportedTaskRole({
  title,
  detail,
}) {
  const normalized = `${title} ${detail}`.toLowerCase();
  if (
    normalized.includes("farm manager") ||
    normalized.includes("manager review") ||
    normalized.includes("manager verifies") ||
    normalized.includes("manager signs off")
  ) {
    return "farm_manager";
  }
  return "farmer";
}

function inferImportedTaskHeadcount({
  phaseName,
  roleRequired,
}) {
  if (roleRequired === "farm_manager") {
    return 1;
  }
  const normalizedPhase = normalizeImportedSentence(phaseName).toLowerCase();
  if (normalizedPhase.includes("nursery")) {
    return 2;
  }
  if (normalizedPhase.includes("transplant")) {
    return 4;
  }
  if (normalizedPhase.includes("harvest")) {
    return 4;
  }
  if (
    normalizedPhase.includes("vegetative") ||
    normalizedPhase.includes("flower") ||
    normalizedPhase.includes("fruit")
  ) {
    return 3;
  }
  return 2;
}

function buildImportedTaskFromLines({
  phaseName,
  dayNumber,
  dateLine,
  taskLines,
  fallbackYear,
}) {
  const parsedDate = parseShortMonthDate(dateLine, fallbackYear);
  const { title, detail } = splitImportedTaskTitleAndDetail(taskLines);
  const roleRequired = inferImportedTaskRole({
    title,
    detail,
  });
  const requiredHeadcount = inferImportedTaskHeadcount({
    phaseName,
    roleRequired,
  });
  const detailWithDayContext = [
    parsedDate ? `Project day ${dayNumber} (${formatIsoDate(parsedDate)}).` : "",
    detail,
  ]
    .filter(Boolean)
    .join(" ");

  return {
    title,
    roleRequired,
    requiredHeadcount,
    weight: 1,
    instructions: detailWithDayContext,
    taskType: "workload",
    sourceTemplateKey: `imported_source_day_${dayNumber}`,
    assignedStaffProfileIds: [],
  };
}

function parseImportedPhaseSections(lines, projectWindow) {
  const phases = [];
  let index = 0;

  while (index < lines.length) {
    const phaseHeaderMatch = normalizeImportedSentence(lines[index]).match(
      /^Phase\s+(\d+)\s*:\s*(.+)$/i,
    );
    if (!phaseHeaderMatch) {
      index += 1;
      continue;
    }

    const order = Number(phaseHeaderMatch[1] || phases.length + 1) || phases.length + 1;
    const phaseName = normalizeImportedSentence(phaseHeaderMatch[2] || `Phase ${order}`);
    index += 1;

    let phaseRange = null;
    while (index < lines.length) {
      const candidate = lines[index];
      if (isImportedPageHeaderLine(candidate) || isImportedTableHeaderLine(candidate)) {
        index += 1;
        continue;
      }
      phaseRange = parseLongDateRange(candidate);
      if (phaseRange) {
        index += 1;
      }
      break;
    }

    const phaseStartDate =
      phaseRange?.startDate ||
      projectWindow?.startDate ||
      null;
    const phaseEndDate =
      phaseRange?.endDate ||
      projectWindow?.endDate ||
      null;
    const fallbackYear =
      phaseStartDate?.getUTCFullYear?.() ||
      projectWindow?.startDate?.getUTCFullYear?.() ||
      new Date().getUTCFullYear();

    const tasks = [];
    while (index < lines.length) {
      const currentLine = lines[index];
      if (isImportedPhaseHeaderLine(currentLine)) {
        break;
      }
      if (
        isImportedPageHeaderLine(currentLine) ||
        isImportedTableHeaderLine(currentLine)
      ) {
        index += 1;
        continue;
      }

      const dayMatch = normalizeImportedSentence(currentLine).match(/^Day\s+(\d+)$/i);
      if (!dayMatch) {
        index += 1;
        continue;
      }

      const dayNumber = Number(dayMatch[1] || tasks.length + 1) || tasks.length + 1;
      index += 1;

      while (
        index < lines.length &&
        (isImportedPageHeaderLine(lines[index]) || isImportedTableHeaderLine(lines[index]))
      ) {
        index += 1;
      }

      const dateLine =
        index < lines.length ? normalizeImportedSentence(lines[index]) : "";
      const parsedDate =
        parseShortMonthDate(dateLine, fallbackYear);
      if (parsedDate) {
        index += 1;
      }

      const taskLines = [];
      while (index < lines.length) {
        const candidate = lines[index];
        if (
          isImportedPhaseHeaderLine(candidate) ||
          isImportedTaskBoundaryLine(candidate)
        ) {
          break;
        }
        if (
          isImportedPageHeaderLine(candidate) ||
          isImportedTableHeaderLine(candidate)
        ) {
          index += 1;
          continue;
        }
        taskLines.push(candidate);
        index += 1;
      }

      tasks.push(
        buildImportedTaskFromLines({
          phaseName,
          dayNumber,
          dateLine,
          taskLines,
          fallbackYear,
        }),
      );
    }

    const estimatedDays =
      Math.max(
        1,
        Number(phaseRange?.dayCount || 0) || tasks.length || 1,
      );
    if (tasks.length > 0) {
      phases.push({
        name: phaseName,
        order,
        estimatedDays,
        phaseType: "finite",
        requiredUnits: 0,
        minRatePerFarmerHour: 0.2,
        targetRatePerFarmerHour: 0.4,
        plannedHoursPerDay: 6,
        biologicalMinDays: estimatedDays,
        startDate: formatIsoDate(phaseStartDate),
        endDate: formatIsoDate(phaseEndDate),
        tasks,
      });
    }
  }

  return phases;
}

function buildProductionDraftImportResponse({
  sourceDocumentContext,
  estateAssetId,
  productId,
  productName,
  domainContext,
  plantingTargets,
  titleFallback = "",
  notesFallback = "",
}) {
  const sourceText = normalizeImportedDocumentText(sourceDocumentContext?.text || "");
  if (!sourceText) {
    return null;
  }

  const lines = sourceText
    .split("\n")
    .map((line) => normalizeImportedSentence(line))
    .filter(Boolean);
  const projectWindowLineIndex = lines.findIndex((line) =>
    /^Project Window$/i.test(line),
  );
  const projectWindow =
    projectWindowLineIndex >= 0 ?
      parseLongDateRange(lines[projectWindowLineIndex + 1] || "")
    : null;
  const phases = parseImportedPhaseSections(lines, projectWindow);
  const totalTaskCount = phases.reduce(
    (sum, phase) => sum + phase.tasks.length,
    0,
  );
  if (phases.length === 0 || totalTaskCount === 0) {
    return null;
  }

  const greenhouseCount =
    extractImportedGreenhouseCount(lines);
  const normalizedPlantingTargets =
    extractImportedPlantingTargets(
      lines,
      plantingTargets,
    );

  const phasesWithScope = phases.map(
    (phase) => ({
      ...phase,
      requiredUnits:
        greenhouseCount > 0 ?
          greenhouseCount
        : Number(
            phase.requiredUnits || 0,
          ) || 0,
    }),
  );
  const normalizedPhaseDays =
    phasesWithScope.reduce(
      (sum, phase) =>
        sum +
        Number(
          phase.estimatedDays || 0,
        ),
      0,
    );
  const startDate =
    formatIsoDate(projectWindow?.startDate) ||
    phasesWithScope[0]?.startDate ||
    "";
  const endDate =
    formatIsoDate(projectWindow?.endDate) ||
    phasesWithScope[
      phasesWithScope.length - 1
    ]?.endDate ||
    "";
  if (!startDate || !endDate) {
    return null;
  }

  const totalEstimatedDays =
    projectWindow?.dayCount > 0 ?
      projectWindow.dayCount
    : normalizedPhaseDays;
  const resolvedTitleFallback =
    normalizeImportedSentence(titleFallback);
  const resolvedProductName =
    normalizeImportedSentence(productName);
  const title =
    resolvedTitleFallback ||
    (resolvedProductName ?
      `${resolvedProductName} Plan`
    : "") ||
    normalizeImportedSentence(
      extractImportedDocumentTitle(lines),
    ) ||
    "Production Plan";
  const notes =
    normalizeImportedSentence(
      extractImportedCorrectionNotes(lines) || notesFallback,
    ) || "";

  return {
    status: "ai_draft_success",
    message: `Draft populated directly from ${sourceDocumentContext?.fileName || "the uploaded document"}.`,
    warnings: [
      {
        code: "SOURCE_DOCUMENT_DIRECT_IMPORT",
        message: `Imported ${totalTaskCount} task rows directly from ${sourceDocumentContext?.fileName || "the uploaded document"}.`,
      },
    ],
    summary: {
      startDate,
      endDate,
      days: totalEstimatedDays,
      weeks: Math.max(1, Math.ceil(totalEstimatedDays / 7)),
      totalTasks: totalTaskCount,
      totalEstimatedDays,
      riskNotes: [],
    },
    draft: {
      title,
      notes,
      estateAssetId,
      productId,
      domainContext,
      startDate,
      endDate,
      aiGenerated: false,
      plantingTargets:
        normalizedPlantingTargets,
      summary: {
        totalTasks: totalTaskCount,
        totalEstimatedDays,
        days: totalEstimatedDays,
        riskNotes: [],
      },
      phases: phasesWithScope,
    },
  };
}

module.exports = {
  extractAiDraftSourceDocumentContext,
  buildProductionDraftImportResponse,
};
