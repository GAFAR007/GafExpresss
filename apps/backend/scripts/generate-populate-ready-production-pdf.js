#!/usr/bin/env node
/**
 * Generate a populate-ready PDF from an uploaded production plan source.
 *
 * Usage:
 *   node apps/backend/scripts/generate-populate-ready-production-pdf.js <input.pdf> <output.pdf>
 */

const fs = require("fs");
const path = require("path");
const {
  extractAiDraftSourceDocumentContext,
  buildProductionDraftImportResponse,
} = require("../services/production_plan_import.service");

function requireArg(value, label) {
  if (value && value.toString().trim()) {
    return value.toString().trim();
  }
  throw new Error(`Missing required ${label}.`);
}

function parseIsoDate(value) {
  const normalized = (value || "").toString().trim();
  if (!normalized) {
    return null;
  }
  const parsed = new Date(`${normalized}T00:00:00.000Z`);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function formatDateLabel(value) {
  const parsed = parseIsoDate(value);
  if (!parsed) {
    return "";
  }
  return new Intl.DateTimeFormat("en-GB", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    timeZone: "UTC",
  }).format(parsed);
}

function formatShortDateLabel(value) {
  const parsed = parseIsoDate(value);
  if (!parsed) {
    return "";
  }
  return new Intl.DateTimeFormat("en-GB", {
    day: "2-digit",
    month: "short",
    timeZone: "UTC",
  }).format(parsed);
}

function formatNumber(value) {
  const parsed = Number(value || 0);
  if (!Number.isFinite(parsed)) {
    return "";
  }
  return parsed.toLocaleString("en-GB");
}

function cleanTaskDetail(value) {
  return (value || "")
    .toString()
    .replace(/^Project day\s+\d+\s+\(\d{4}-\d{2}-\d{2}\)\.\s*/i, "")
    .trim();
}

function buildDocumentLines({
  sourceDocumentContext,
  importResponse,
}) {
  const draft = importResponse.draft || {};
  const phases = Array.isArray(draft.phases) ? draft.phases : [];
  const plantingTargets = draft.plantingTargets || {};
  const greenhouseCount = Number(phases[0]?.requiredUnits || 0) || 0;
  const totalPlants = Number(plantingTargets.plannedPlantingQuantity || 0) || 0;
  const plantsPerGreenhouse =
    greenhouseCount > 0 && totalPlants > 0
      ? Math.round(totalPlants / greenhouseCount)
      : 0;
  const projectDays = Number(importResponse?.summary?.days || 0) || 0;
  const overviewFocus = (phase) =>
    Array.isArray(phase.tasks) && phase.tasks.length > 0
      ? cleanTaskDetail(phase.tasks[0].instructions || phase.tasks[0].title)
      : "Operational tasks";

  const lines = [
    draft.title || "Production Plan",
    "Populate-ready source plan generated from a corrected working draft.",
    "Estate",
    "Gafars Estate",
    "Crop",
    "Bell Pepper",
    "Project Window",
    `${formatDateLabel(draft.startDate)} to ${formatDateLabel(draft.endDate)}`,
    "Duration",
    `${projectDays} days`,
    "Greenhouses",
    greenhouseCount > 0 ? `${greenhouseCount} greenhouses` : "",
    "Planting Basis",
    plantsPerGreenhouse > 0
      ? `${formatNumber(plantsPerGreenhouse)} plants per greenhouse (${formatNumber(totalPlants)} total planned plants)`
      : `${formatNumber(totalPlants)} ${plantingTargets.plannedPlantingUnit || "plants"}`,
    "Estimated Harvest",
    plantingTargets.estimatedHarvestQuantity
      ? `${formatNumber(plantingTargets.estimatedHarvestQuantity)} ${plantingTargets.estimatedHarvestUnit || ""}`.trim()
      : "",
    "Phase Allocation Overview",
    "Phase",
    "Date range",
    "Days",
    "Operational focus",
  ].filter(Boolean);

  for (const phase of phases) {
    lines.push(phase.name || "Phase");
    lines.push(
      `${formatDateLabel(phase.startDate)} - ${formatDateLabel(phase.endDate)}`,
    );
    lines.push(`${phase.estimatedDays || 0}`);
    lines.push(overviewFocus(phase));
  }

  lines.push("Correction Notes");
  lines.push(
    "This populate-ready PDF keeps a strict phase/day/task structure so the draft importer can rebuild the full plan without collapsing it into a sparse summary.",
  );
  lines.push(
    `Uploaded source recovered about ${sourceDocumentContext.taskLineEstimate || 0} task-like lines and this cleaned document preserves the full ${importResponse.summary.totalTasks || 0}-task schedule.`,
  );

  let projectDay = 1;
  for (const [phaseIndex, phase] of phases.entries()) {
    lines.push(`Phase ${phaseIndex + 1}: ${phase.name || `Phase ${phaseIndex + 1}`}`);
    lines.push(
      `${formatDateLabel(phase.startDate)} to ${formatDateLabel(phase.endDate)} ${phase.estimatedDays || 0} day(s)`,
    );
    lines.push("Project Day");
    lines.push("Date");
    lines.push("Task");
    lines.push("Detail");

    const phaseStartDate = parseIsoDate(phase.startDate);
    const tasks = Array.isArray(phase.tasks) ? phase.tasks : [];
    for (let taskIndex = 0; taskIndex < tasks.length; taskIndex += 1) {
      const task = tasks[taskIndex] || {};
      const taskDate = phaseStartDate
        ? new Date(phaseStartDate.getTime() + taskIndex * 86400000)
        : null;
      const taskDateIso = taskDate ? taskDate.toISOString().slice(0, 10) : "";
      lines.push(`Day ${projectDay}`);
      lines.push(taskDate ? formatShortDateLabel(taskDateIso) : "");
      lines.push((task.title || "Imported task").toString().trim());
      lines.push(
        cleanTaskDetail(task.instructions || "Imported from uploaded source document."),
      );
      projectDay += 1;
    }
  }

  return lines;
}

function escapePdfText(value) {
  return (value || "")
    .toString()
    .replace(/\\/g, "\\\\")
    .replace(/\(/g, "\\(")
    .replace(/\)/g, "\\)")
    .replace(/[–—]/g, "-");
}

function chunkLines(lines, perPage = 44) {
  const chunks = [];
  for (let index = 0; index < lines.length; index += perPage) {
    chunks.push(lines.slice(index, index + perPage));
  }
  return chunks;
}

function buildPdfBuffer(lines) {
  const pageChunks = chunkLines(lines);
  const objects = [];
  const pageObjectNumbers = [];

  objects.push("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
  objects.push("2 0 obj\n<< /Type /Pages /Kids [PAGES] /Count COUNT >>\nendobj\n");
  objects.push("3 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n");

  let nextObjectNumber = 4;
  for (const pageLines of pageChunks) {
    const pageObjectNumber = nextObjectNumber;
    const contentObjectNumber = nextObjectNumber + 1;
    pageObjectNumbers.push(`${pageObjectNumber} 0 R`);

    const streamLines = [
      "BT",
      "/F1 10 Tf",
      "14 TL",
      "50 780 Td",
    ];

    pageLines.forEach((line, lineIndex) => {
      const prefix = lineIndex === 0 ? "" : "T* ";
      streamLines.push(`${prefix}(${escapePdfText(line)}) Tj`);
    });

    streamLines.push("ET");
    const streamContent = `${streamLines.join("\n")}\n`;
    const streamLength = Buffer.byteLength(streamContent, "utf8");

    objects.push(
      `${pageObjectNumber} 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents ${contentObjectNumber} 0 R >>\nendobj\n`,
    );
    objects.push(
      `${contentObjectNumber} 0 obj\n<< /Length ${streamLength} >>\nstream\n${streamContent}endstream\nendobj\n`,
    );
    nextObjectNumber += 2;
  }

  objects[1] = objects[1]
    .replace("PAGES", pageObjectNumbers.join(" "))
    .replace("COUNT", String(pageChunks.length));

  let pdf = "%PDF-1.4\n";
  const offsets = [0];
  for (const object of objects) {
    offsets.push(Buffer.byteLength(pdf, "utf8"));
    pdf += object;
  }
  const xrefOffset = Buffer.byteLength(pdf, "utf8");
  pdf += `xref\n0 ${objects.length + 1}\n`;
  pdf += "0000000000 65535 f \n";
  for (let index = 1; index <= objects.length; index += 1) {
    pdf += `${String(offsets[index]).padStart(10, "0")} 00000 n \n`;
  }
  pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF`;
  return Buffer.from(pdf, "utf8");
}

function main() {
  const inputPath = requireArg(process.argv[2], "input pdf path");
  const outputPath = requireArg(process.argv[3], "output pdf path");

  const bytes = fs.readFileSync(inputPath);
  const sourceDocumentContext = extractAiDraftSourceDocumentContext({
    fileName: path.basename(inputPath),
    extension: "pdf",
    contentBase64: bytes.toString("base64"),
  });
  if (!sourceDocumentContext?.text) {
    throw new Error("Could not extract planning text from the input PDF.");
  }

  const importResponse = buildProductionDraftImportResponse({
    sourceDocumentContext,
    estateAssetId: "import-preview-estate",
    productId: "import-preview-product",
    productName: "Bell Pepper",
    domainContext: "farm",
    plantingTargets: {
      materialType: "seedling",
      plannedPlantingQuantity: 2500,
      plannedPlantingUnit: "plant",
      estimatedHarvestQuantity: 5500,
      estimatedHarvestUnit: "kg",
    },
    titleFallback: "Bell Pepper Greenhouse Production Plan",
    notesFallback:
      "Populate-ready PDF rebuilt from the corrected greenhouse source plan.",
  });
  if (!importResponse?.draft?.phases?.length) {
    throw new Error("Could not build an imported draft from the input PDF.");
  }

  const lines = buildDocumentLines({
    sourceDocumentContext,
    importResponse,
  });
  const pdfBuffer = buildPdfBuffer(lines);

  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, pdfBuffer);

  console.log(
    JSON.stringify(
      {
        outputPath,
        phaseCount: importResponse.draft.phases.length,
        totalTasks: importResponse.summary.totalTasks,
        projectDays: importResponse.summary.days,
      },
      null,
      2,
    ),
  );
}

main();
