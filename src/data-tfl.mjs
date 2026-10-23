// Fetches live line status from the TfL Unified API (no key needed at this volume)
// and normalizes it for the TfL screen.

// TfL severities that are not disruptions: Good Service, No Issues, Information.
const FINE = new Set([10, 18, 19]);
const CLOSED = 20; // "Service Closed" — normal overnight, shown plainly rather than as an alert.

function cleanReason(reason, name) {
  // TfL prefixes reasons with the line name, e.g. "Northern Line: Severe delays ..."
  const prefix = new RegExp(`^${name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}( line)?:\\s*`, "i");
  return reason.replace(prefix, "").replace(/\s+/g, " ").trim();
}

export async function fetchTfl(config) {
  const modes = config.tfl?.modes ?? "tube,elizabeth-line,overground,dlr";
  const featuredId = config.tfl?.featured ?? "northern";
  try {
    const res = await fetch(`https://api.tfl.gov.uk/Line/Mode/${modes}/Status`);
    if (!res.ok) throw new Error(`TfL API returned ${res.status}`);
    const raw = await res.json();

    const lines = raw.map((l) => {
      const sts = l.lineStatuses ?? [];
      const trouble = sts.filter((s) => !FINE.has(s.statusSeverity) && s.statusSeverity !== CLOSED);
      const closed = sts.filter((s) => s.statusSeverity === CLOSED);
      const shown = trouble.length ? trouble : closed.length ? closed : sts;
      return {
        id: l.id,
        name: l.name,
        mode: l.modeName,
        status: [...new Set(shown.map((s) => s.statusSeverityDescription))].join(" · ") || "Unknown",
        disrupted: trouble.length > 0,
        severity: Math.min(10, ...shown.map((s) => s.statusSeverity)),
        reasons: [...new Set(shown.map((s) => s.reason).filter(Boolean).map((r) => cleanReason(r, l.name)))],
      };
    });

    return {
      generatedAt: new Date(),
      lines,
      featured: lines.find((l) => l.id === featuredId) ?? null,
      error: null,
    };
  } catch (e) {
    return { generatedAt: new Date(), lines: [], featured: null, error: e.message };
  }
}
