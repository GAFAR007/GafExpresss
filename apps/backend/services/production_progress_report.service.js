/**
 * apps/backend/services/production_progress_report.service.js
 * -----------------------------------------------------------
 * WHAT:
 * - Builds styled production progress report markup and login-safe deep links.
 *
 * WHY:
 * - Keeps progress downloads and email sharing on the same report template.
 * - Ensures recipients land back on the intended production page after login.
 *
 * HOW:
 * - Normalizes the requested production route against the current plan id.
 * - Builds one HTML report + plain-text summary from the visible plan detail.
 * - Produces a login-first URL that redirects to the live page after auth.
 */

const FRONTEND_BASE_URL = (
  process.env.FRONTEND_BASE_URL || "http://localhost:5173"
)
  .trim()
  .replace(/\/+$/, "");

function normalizeProductionProgressRoutePath({ routePath, planId }) {
  const normalizedPlanId = (planId || "").toString().trim();
  const fallbackPath = normalizedPlanId
    ? `/business-production/${normalizedPlanId}`
    : "/business-production";
  const normalizedRoutePath = (routePath || "").toString().trim();
  if (!normalizedRoutePath || !normalizedRoutePath.startsWith("/")) {
    return fallbackPath;
  }
  if (normalizedRoutePath.includes("://")) {
    return fallbackPath;
  }
  if (
    normalizedPlanId &&
    !normalizedRoutePath.startsWith(`/business-production/${normalizedPlanId}`)
  ) {
    return fallbackPath;
  }
  return normalizedRoutePath;
}

function normalizeRecipientEmail(value) {
  const normalized = (value || "").toString().trim();
  if (!normalized || normalized.includes(" ") || !normalized.includes("@")) {
    return "";
  }
  return normalized;
}

function buildProductionProgressLoginUrl(routePath, recipientEmail) {
  const searchParams = new URLSearchParams();
  const normalizedEmail = normalizeRecipientEmail(recipientEmail);
  if (normalizedEmail) {
    searchParams.set("email", normalizedEmail);
  }
  searchParams.set("next", routePath);
  return `${FRONTEND_BASE_URL}/#/login?${searchParams.toString()}`;
}

function buildProductionProgressLiveUrl(routePath) {
  return `${FRONTEND_BASE_URL}/#${routePath}`;
}

function escapeHtml(value) {
  return (value || "")
    .toString()
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function humanizeLabel(value) {
  const normalized = (value || "").toString().trim();
  if (!normalized) {
    return "Unknown";
  }
  return normalized
    .split("_")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1).toLowerCase())
    .join(" ");
}

function formatDateLabel(value) {
  if (!value) {
    return "Not set";
  }
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return "Not set";
  }
  return parsed.toISOString().slice(0, 10);
}

function formatDateTimeLabel(value) {
  if (!value) {
    return "Not set";
  }
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return "Not set";
  }
  return parsed.toISOString().replace("T", " ").slice(0, 16) + " UTC";
}

function formatNumber(value, options = {}) {
  const numeric = Number(value || 0);
  if (!Number.isFinite(numeric)) {
    return "0";
  }
  return new Intl.NumberFormat("en-US", options).format(numeric);
}

function formatPercent(value) {
  const numeric = Number(value || 0);
  if (!Number.isFinite(numeric)) {
    return "0%";
  }
  return `${Math.round(numeric * 100)}%`;
}

function formatDayQuantity(value) {
  const numeric = Number(value || 0);
  if (!Number.isFinite(numeric)) {
    return "0";
  }
  if (Number.isInteger(numeric)) {
    return numeric.toString();
  }
  return numeric.toFixed(1);
}

function slugifyFileSegment(value) {
  return (value || "")
    .toString()
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 64);
}

function buildMetricCard({ label, value, detail, accentClass = "" }) {
  return `
    <div class="metric-card ${accentClass}">
      <div class="metric-label">${escapeHtml(label)}</div>
      <div class="metric-value">${escapeHtml(value)}</div>
      <div class="metric-detail">${escapeHtml(detail)}</div>
    </div>
  `;
}

function buildSectionHeader({ kicker, title, subtitle }) {
  return `
    <div class="section-header">
      <div class="section-line"></div>
      <div>
        <p class="section-kicker">${escapeHtml(kicker)}</p>
        <h2 class="section-title">${escapeHtml(title)}</h2>
        <p class="section-subtitle">${escapeHtml(subtitle)}</p>
      </div>
    </div>
  `;
}

function buildTimelineRowHtml(row) {
  const taskTitle = row?.taskTitle?.trim() || "Untitled task";
  const phaseName = row?.phaseName?.trim() || "Unknown phase";
  const farmerName = row?.farmerName?.trim() || "Unknown staff";
  const notes = row?.notes?.trim() || "";
  const approvalLabel = humanizeLabel(row?.approvalState || "pending_approval");
  const activityBits = [
    row?.activityType ? humanizeLabel(row.activityType) : "",
    row?.activityQuantity ? formatDayQuantity(row.activityQuantity) : "",
    row?.quantityUnit?.trim() || "",
  ]
    .filter(Boolean)
    .join(" ");
  return `
    <article class="activity-card">
      <div class="activity-top">
        <div>
          <div class="activity-title">${escapeHtml(taskTitle)}</div>
          <div class="activity-meta">${escapeHtml(`${phaseName} • ${farmerName}`)}</div>
        </div>
        <div class="activity-pill">${escapeHtml(approvalLabel)}</div>
      </div>
      <div class="activity-grid">
        <div class="activity-stat">
          <div class="activity-stat-label">Expected</div>
          <div class="activity-stat-value">${escapeHtml(formatDayQuantity(row?.expectedPlots))}</div>
        </div>
        <div class="activity-stat">
          <div class="activity-stat-label">Actual</div>
          <div class="activity-stat-value">${escapeHtml(formatDayQuantity(row?.actualPlots))}</div>
        </div>
        <div class="activity-stat">
          <div class="activity-stat-label">Delay</div>
          <div class="activity-stat-value">${escapeHtml(humanizeLabel(row?.delayReason || row?.delay || "none"))}</div>
        </div>
      </div>
      ${
        activityBits
          ? `<div class="activity-inline">Activity: ${escapeHtml(activityBits)}</div>`
          : ""
      }
      ${
        row?.approvedAt
          ? `<div class="activity-inline">Approved at ${escapeHtml(formatDateTimeLabel(row.approvedAt))}</div>`
          : ""
      }
      ${
        notes
          ? `<div class="activity-note">${escapeHtml(notes)}</div>`
          : ""
      }
    </article>
  `;
}

function buildPhaseRowHtml(phase) {
  const totalTasks = Math.max(0, Number(phase?.totalTasks || 0));
  const completedTasks = Math.max(0, Number(phase?.completedTasks || 0));
  const completionRate = Math.max(0, Math.min(1, Number(phase?.completionRate || 0)));
  return `
    <div class="phase-row">
      <div class="phase-row-top">
        <div class="phase-name">${escapeHtml(phase?.name || "Unnamed phase")}</div>
        <div class="phase-count">${escapeHtml(`${completedTasks}/${totalTasks} • ${formatPercent(completionRate)}`)}</div>
      </div>
      <div class="progress-track">
        <div class="progress-fill" style="width: ${Math.round(completionRate * 100)}%;"></div>
      </div>
    </div>
  `;
}

function buildOutputRowHtml([unitLabel, quantity]) {
  return `
    <div class="output-pill">
      <span class="output-pill-qty">${escapeHtml(formatDayQuantity(quantity))}</span>
      <span>${escapeHtml(unitLabel || "units")}</span>
    </div>
  `;
}

function buildProductionProgressReport({ detailPayload, routePath, toEmail }) {
  const safeDetailPayload =
    detailPayload && typeof detailPayload === "object" ? detailPayload : {};
  const plan = safeDetailPayload.plan || {};
  const kpis = safeDetailPayload.kpis || null;
  const outputs = Array.isArray(safeDetailPayload.outputs)
    ? safeDetailPayload.outputs
    : [];
  const timelineRows = Array.isArray(safeDetailPayload.timelineRows)
    ? safeDetailPayload.timelineRows
    : [];
  const attendanceImpact = safeDetailPayload.attendanceImpact || null;
  const preorderSummary = safeDetailPayload.preorderSummary || null;
  const normalizedRoutePath = normalizeProductionProgressRoutePath({
    routePath,
    planId: plan?._id || plan?.id,
  });
  const reportUrl = buildProductionProgressLoginUrl(
    normalizedRoutePath,
    toEmail,
  );
  const livePageUrl = buildProductionProgressLiveUrl(normalizedRoutePath);
  const generatedAt = new Date();
  const safePlanTitle = plan?.title?.trim() || "Untitled production plan";
  const subject = `Production progress report: ${safePlanTitle}`;
  const fileNameStem =
    slugifyFileSegment(safePlanTitle) ||
    slugifyFileSegment(plan?._id || plan?.id || "production-plan");
  const fileName = `${fileNameStem}-progress-report-${generatedAt
    .toISOString()
    .slice(0, 10)}.html`;
  const outputEntries =
    kpis?.outputByUnit && typeof kpis.outputByUnit === "object"
      ? Object.entries(kpis.outputByUnit).sort((left, right) =>
          Number(right[1] || 0) - Number(left[1] || 0),
        )
      : [];
  const phaseCompletion = Array.isArray(kpis?.phaseCompletion)
    ? kpis.phaseCompletion
    : [];
  const recentRows = timelineRows.slice(0, 12);
  const readyForSaleCount = outputs.filter((output) => output?.readyForSale === true)
    .length;
  const totalTasks = Number(kpis?.totalTasks || 0);
  const completedTasks = Number(kpis?.completedTasks || 0);
  const onTimeRate = kpis?.onTimeRate;
  const avgDelayDays = Number(kpis?.avgDelayDays || 0);
  const planStatus = humanizeLabel(plan?.status || "draft");
  const productState = humanizeLabel(
    safeDetailPayload?.product?.productionState || "not_available",
  );
  const scheduleRange = `${formatDateLabel(plan?.startDate)} - ${formatDateLabel(
    plan?.endDate,
  )}`;
  const statusBanner = [
    `Status: ${planStatus}`,
    `Schedule: ${scheduleRange}`,
    `Generated: ${formatDateTimeLabel(generatedAt)}`,
  ].join(" | ");
  const metricsHtml = kpis
    ? [
        buildMetricCard({
          label: "Total tasks",
          value: formatNumber(totalTasks),
          detail: `${formatNumber(timelineRows.length)} progress row(s) recorded`,
        }),
        buildMetricCard({
          label: "Completed",
          value: formatNumber(completedTasks),
          detail: `${formatPercent(kpis.completionRate)} completion rate`,
          accentClass: "cool",
        }),
        buildMetricCard({
          label: "On time",
          value: formatPercent(onTimeRate),
          detail: "Completed tasks that landed on or before due date",
        }),
        buildMetricCard({
          label: "Avg delay",
          value: `${avgDelayDays.toFixed(1)} day(s)`,
          detail: "Average delay across completed work",
          accentClass: "warm",
        }),
      ].join("")
    : `
        <div class="empty-state">
          KPI summaries are not available for this viewer. The report still includes recent activity and live access back into the plan.
        </div>
      `;
  const outputHtml = outputEntries.length > 0
    ? outputEntries.map(buildOutputRowHtml).join("")
    : `
        <div class="empty-state compact">
          No output quantities have been recorded yet.
        </div>
      `;
  const phaseHtml = phaseCompletion.length > 0
    ? phaseCompletion.map(buildPhaseRowHtml).join("")
    : `
        <div class="empty-state compact">
          Phase completion will appear once tasks start closing or approved progress accumulates.
        </div>
      `;
  const recentActivityHtml = recentRows.length > 0
    ? recentRows.map(buildTimelineRowHtml).join("")
    : `
        <div class="empty-state">
          No recent activity has been saved for this plan yet.
        </div>
      `;
  const attendanceHtml = attendanceImpact
    ? [
        buildMetricCard({
          label: "Tracked days",
          value: formatNumber(attendanceImpact.totalRollupDays || 0),
          detail: "Daily rollup days included in attendance KPIs",
        }),
        buildMetricCard({
          label: "Attendance cover",
          value: formatPercent(attendanceImpact.attendanceCoverageRate || 0),
          detail: "Assigned slots covered by attended staff",
          accentClass: "cool",
        }),
        buildMetricCard({
          label: "Progress linked",
          value: formatPercent(attendanceImpact.attendanceLinkedProgressRate || 0),
          detail: "Progress rows backed by attendance records",
        }),
        buildMetricCard({
          label: "Plots / attended hr",
          value: formatDayQuantity(attendanceImpact.plotsPerAttendedHour || 0),
          detail: "Execution efficiency from attendance-linked output",
          accentClass: "warm",
        }),
      ].join("")
    : `
        <div class="empty-state compact">
          Attendance-linked KPIs are not available yet for this plan.
        </div>
      `;
  const preorderHtml = preorderSummary
    ? `
        <div class="summary-banner">
          Pre-order summary: ${escapeHtml(
            `${preorderSummary.preorderEnabled ? "Enabled" : "Disabled"} • effective cap ${formatDayQuantity(preorderSummary.effectiveCap || 0)} • remaining ${formatDayQuantity(preorderSummary.preorderRemainingQuantity || 0)} • confidence ${formatPercent(preorderSummary.confidenceScore || 0)}`,
          )}
        </div>
      `
    : "";
  const html = `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${escapeHtml(subject)}</title>
    <style>
      :root {
        --page-bg: #eff6f4;
        --surface: #ffffff;
        --surface-soft: #f7fbfa;
        --surface-muted: #ecf5f2;
        --border: #d4e6e1;
        --text: #122b29;
        --muted: #5e7470;
        --accent: #0f766e;
        --accent-soft: #d6f2ec;
        --accent-cool: #1d4ed8;
        --accent-warm: #c47a10;
        --shadow: 0 18px 42px rgba(12, 47, 44, 0.08);
      }

      * { box-sizing: border-box; }

      body {
        margin: 0;
        background:
          radial-gradient(circle at top left, rgba(15, 118, 110, 0.10), transparent 28%),
          linear-gradient(180deg, #f9fcfb 0%, var(--page-bg) 100%);
        color: var(--text);
        font-family: "Segoe UI", "Helvetica Neue", Arial, sans-serif;
        line-height: 1.55;
      }

      .page-shell {
        max-width: 1180px;
        margin: 0 auto;
        padding: 24px;
      }

      .hero-card {
        padding: 28px;
        border-radius: 28px;
        background: linear-gradient(135deg, #0b3b39 0%, #0f766e 55%, #20a393 100%);
        color: #ffffff;
        box-shadow: var(--shadow);
      }

      .hero-eyebrow {
        margin: 0 0 10px;
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: 0.14em;
        font-weight: 700;
        opacity: 0.86;
      }

      .hero-title {
        margin: 0;
        font-size: clamp(28px, 4vw, 40px);
        line-height: 1.08;
      }

      .hero-copy {
        margin: 14px 0 0;
        max-width: 760px;
        color: rgba(255, 255, 255, 0.92);
      }

      .hero-banner {
        margin-top: 16px;
        padding: 14px 16px;
        border-radius: 18px;
        background: rgba(255, 255, 255, 0.12);
        border-left: 5px solid rgba(255, 255, 255, 0.78);
      }

      .hero-actions {
        display: flex;
        gap: 12px;
        flex-wrap: wrap;
        margin-top: 18px;
      }

      .cta-button {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-height: 44px;
        padding: 0 18px;
        border-radius: 999px;
        background: #ffffff;
        color: #0b4f4a;
        text-decoration: none;
        font-weight: 700;
      }

      .cta-link {
        color: #ffffff;
        text-decoration: none;
        font-weight: 600;
        opacity: 0.9;
      }

      .copy-panel {
        margin-top: 18px;
        padding: 16px;
        border-radius: 20px;
        background: rgba(255, 255, 255, 0.12);
        border: 1px solid rgba(255, 255, 255, 0.18);
      }

      .copy-title {
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: 0.12em;
        font-weight: 700;
        opacity: 0.86;
      }

      .copy-grid {
        display: grid;
        gap: 10px;
        margin-top: 12px;
      }

      .copy-item {
        padding: 12px 14px;
        border-radius: 16px;
        background: rgba(5, 22, 21, 0.18);
        border: 1px solid rgba(255, 255, 255, 0.16);
      }

      .copy-label {
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        font-weight: 700;
        opacity: 0.82;
      }

      .copy-value {
        margin-top: 8px;
        color: #ffffff;
        font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
        font-size: 13px;
        line-height: 1.5;
        word-break: break-all;
        overflow-wrap: anywhere;
      }

      .report-grid {
        display: grid;
        grid-template-columns: repeat(12, minmax(0, 1fr));
        gap: 18px;
        margin-top: 20px;
      }

      .section-card {
        grid-column: span 6;
        padding: 22px;
        border-radius: 24px;
        background: var(--surface);
        border: 1px solid var(--border);
        box-shadow: var(--shadow);
      }

      .section-span {
        grid-column: 1 / -1;
      }

      .section-header {
        display: flex;
        gap: 14px;
        align-items: flex-start;
        margin-bottom: 16px;
      }

      .section-line {
        width: 5px;
        min-height: 54px;
        border-radius: 999px;
        background: linear-gradient(180deg, var(--accent), #64c9bb);
        flex-shrink: 0;
      }

      .section-kicker {
        margin: 0 0 4px;
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: 0.12em;
        color: var(--accent);
        font-weight: 700;
      }

      .section-title {
        margin: 0;
        font-size: 24px;
        line-height: 1.15;
      }

      .section-subtitle {
        margin: 6px 0 0;
        color: var(--muted);
        font-size: 14px;
      }

      .summary-banner {
        padding: 14px 16px;
        border-radius: 18px;
        background: var(--surface-muted);
        border: 1px solid var(--border);
        border-left: 5px solid var(--accent);
        color: var(--text);
      }

      .metric-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
        gap: 12px;
      }

      .metric-card {
        padding: 16px;
        border-radius: 18px;
        background: var(--surface-soft);
        border: 1px solid var(--border);
        border-top: 4px solid var(--accent);
      }

      .metric-card.cool {
        border-top-color: var(--accent-cool);
      }

      .metric-card.warm {
        border-top-color: var(--accent-warm);
      }

      .metric-label {
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        color: var(--muted);
        font-weight: 700;
      }

      .metric-value {
        margin-top: 8px;
        font-size: 22px;
        font-weight: 700;
      }

      .metric-detail {
        margin-top: 8px;
        color: var(--muted);
        font-size: 14px;
      }

      .output-wrap,
      .phase-wrap,
      .activity-stack {
        display: grid;
        gap: 12px;
      }

      .output-pill {
        display: inline-flex;
        align-items: center;
        gap: 10px;
        min-height: 40px;
        padding: 10px 14px;
        border-radius: 999px;
        background: var(--accent-soft);
        border: 1px solid #c0e3dd;
        font-weight: 600;
      }

      .output-pill-qty {
        font-size: 18px;
        font-weight: 800;
      }

      .phase-row {
        padding: 14px 16px;
        border-radius: 18px;
        border: 1px solid var(--border);
        background: var(--surface-soft);
      }

      .phase-row-top {
        display: flex;
        justify-content: space-between;
        gap: 12px;
        align-items: center;
        margin-bottom: 10px;
      }

      .phase-name {
        font-weight: 700;
      }

      .phase-count {
        color: var(--muted);
        font-size: 14px;
        font-weight: 600;
      }

      .progress-track {
        width: 100%;
        height: 8px;
        border-radius: 999px;
        background: #dcebe6;
        overflow: hidden;
      }

      .progress-fill {
        height: 100%;
        border-radius: 999px;
        background: linear-gradient(90deg, var(--accent), #63c8bb);
      }

      .activity-card {
        padding: 16px;
        border-radius: 18px;
        background: var(--surface-soft);
        border: 1px solid var(--border);
        border-left: 5px solid var(--accent);
      }

      .activity-top {
        display: flex;
        justify-content: space-between;
        gap: 12px;
        align-items: flex-start;
      }

      .activity-title {
        font-size: 18px;
        font-weight: 700;
      }

      .activity-meta {
        margin-top: 4px;
        color: var(--muted);
        font-size: 14px;
      }

      .activity-pill {
        min-height: 34px;
        padding: 8px 12px;
        border-radius: 999px;
        background: var(--accent-soft);
        border: 1px solid #c0e3dd;
        color: #0d5953;
        font-size: 13px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.06em;
      }

      .activity-grid {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 10px;
        margin-top: 14px;
      }

      .activity-stat {
        padding: 12px;
        border-radius: 14px;
        background: #ffffff;
        border: 1px solid var(--border);
      }

      .activity-stat-label {
        color: var(--muted);
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        font-weight: 700;
      }

      .activity-stat-value {
        margin-top: 8px;
        font-size: 18px;
        font-weight: 700;
      }

      .activity-inline,
      .activity-note,
      .empty-state {
        margin-top: 12px;
        padding: 12px 14px;
        border-radius: 14px;
        background: #ffffff;
        border: 1px solid var(--border);
        color: var(--muted);
      }

      .empty-state.compact {
        margin-top: 0;
      }

      .footer-note {
        margin-top: 18px;
        text-align: center;
        color: var(--muted);
        font-size: 13px;
      }

      @media (max-width: 920px) {
        .section-card {
          grid-column: 1 / -1;
        }
      }

      @media (max-width: 720px) {
        .page-shell {
          padding: 14px;
        }

        .hero-card,
        .section-card {
          padding: 18px;
        }

        .activity-grid {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </head>
  <body>
    <div class="page-shell">
      <header class="hero-card">
        <p class="hero-eyebrow">Production progress report</p>
        <h1 class="hero-title">${escapeHtml(safePlanTitle)}</h1>
        <p class="hero-copy">
          A live progress snapshot covering completion, outputs, phase movement, and the latest approved or pending activity captured against this production plan.
        </p>
        <div class="hero-banner">${escapeHtml(statusBanner)}</div>
        <div class="hero-actions">
          <a class="cta-button" href="${escapeHtml(reportUrl)}">Open this page after login</a>
          <a class="cta-link" href="${escapeHtml(livePageUrl)}">Direct live page</a>
        </div>
        <div class="copy-panel">
          <div class="copy-title">Copyable links</div>
          <div class="copy-grid">
            <div class="copy-item">
              <div class="copy-label">Open after login</div>
              <div class="copy-value">${escapeHtml(reportUrl)}</div>
            </div>
            <div class="copy-item">
              <div class="copy-label">Direct live page</div>
              <div class="copy-value">${escapeHtml(livePageUrl)}</div>
            </div>
          </div>
        </div>
      </header>

      <main class="report-grid">
        <section class="section-card">
          ${buildSectionHeader({
            kicker: "Overview",
            title: "Progress at a glance",
            subtitle:
              "Top-line completion, pace, and operational status for the visible production scope.",
          })}
          <div class="metric-grid">${metricsHtml}</div>
          ${preorderHtml}
        </section>

        <section class="section-card">
          ${buildSectionHeader({
            kicker: "Plan context",
            title: "Execution context",
            subtitle:
              "The live plan status, schedule window, and product lifecycle state currently visible in the app.",
          })}
          <div class="metric-grid">
            ${buildMetricCard({
              label: "Plan status",
              value: planStatus,
              detail: `Business mode: ${humanizeLabel(plan?.domainContext || "business")}`,
            })}
            ${buildMetricCard({
              label: "Schedule range",
              value: scheduleRange,
              detail: `${formatNumber(
                Array.isArray(safeDetailPayload.tasks) ? safeDetailPayload.tasks.length : 0,
              )} task(s) currently loaded`,
              accentClass: "cool",
            })}
            ${buildMetricCard({
              label: "Product state",
              value: productState,
              detail: `${formatNumber(outputs.length)} output record(s), ${formatNumber(
                readyForSaleCount,
              )} ready for sale`,
            })}
            ${buildMetricCard({
              label: "Live page",
              value: humanizeLabel(
                normalizedRoutePath.includes("/insights") ? "insights view" : "workspace view",
              ),
              detail: "The attached link returns the reader to this exact production page after sign-in.",
              accentClass: "warm",
            })}
          </div>
        </section>

        <section class="section-card">
          ${buildSectionHeader({
            kicker: "Outputs",
            title: "Output snapshot",
            subtitle:
              "Units already recorded from this production plan.",
          })}
          <div class="output-wrap">${outputHtml}</div>
        </section>

        <section class="section-card">
          ${buildSectionHeader({
            kicker: "Phases",
            title: "Phase progress",
            subtitle:
              "Which phases are moving and which ones still need execution.",
          })}
          <div class="phase-wrap">${phaseHtml}</div>
        </section>

        <section class="section-card section-span">
          ${buildSectionHeader({
            kicker: "People",
            title: "Attendance-linked impact",
            subtitle:
              "Attendance and execution efficiency signals derived from the same progress records.",
          })}
          <div class="metric-grid">${attendanceHtml}</div>
        </section>

        <section class="section-card section-span">
          ${buildSectionHeader({
            kicker: "Activity",
            title: "Recent progress feed",
            subtitle:
              "Recent task logs, approvals, notes, and actual-vs-expected movement.",
          })}
          <div class="activity-stack">${recentActivityHtml}</div>
        </section>
      </main>

      <div class="footer-note">
        Generated from the production app. Use the sign-in link above to reopen the same page inside the live workspace.
      </div>
    </div>
  </body>
</html>`;

  const textLines = [
    subject,
    "",
    `Plan status: ${planStatus}`,
    `Schedule: ${scheduleRange}`,
    `Total tasks: ${formatNumber(totalTasks)}`,
    `Completed: ${formatNumber(completedTasks)}`,
    `On time: ${kpis ? formatPercent(onTimeRate) : "Not available"}`,
    `Average delay: ${kpis ? `${avgDelayDays.toFixed(1)} day(s)` : "Not available"}`,
    `Recent activity rows: ${formatNumber(timelineRows.length)}`,
    "",
    `Open after login: ${reportUrl}`,
    `Direct live page: ${livePageUrl}`,
  ];

  return {
    fileName,
    subject,
    routePath: normalizedRoutePath,
    reportUrl,
    livePageUrl,
    html,
    text: textLines.join("\n"),
  };
}

module.exports = {
  buildProductionProgressReport,
  normalizeProductionProgressRoutePath,
  buildProductionProgressLoginUrl,
};
