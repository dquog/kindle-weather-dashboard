// Builds the TfL status screen. Same frame/header as the weather screen.
import { frameCss, pageHeader, pageFooter, updatedStamp } from "./frame.mjs";

// Official TfL line colours; they turn into distinct greys on the e-ink screen.
const COLOURS = {
  bakerloo: "#B36305", central: "#E32017", circle: "#FFD300", district: "#00782A",
  "hammersmith-city": "#F3A9BB", jubilee: "#A0A5A9", metropolitan: "#9B0056",
  northern: "#000000", piccadilly: "#003688", victoria: "#0098D4", "waterloo-city": "#95CDBA",
  elizabeth: "#6950A1", dlr: "#00A4A7", liberty: "#5D6061", lioness: "#FAA61A",
  mildmay: "#006FE6", suffragette: "#18A95D", weaver: "#893B67", windrush: "#DC241F",
};

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const lineName = (l) => (l.mode === "tube" ? `${l.name} line` : l.name);

export function buildTflHtml(t, { width, height }) {
  const dateStr = t.generatedAt.toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long" });
  const updated = updatedStamp(t.generatedAt);

  let body;
  if (t.error) {
    body = `<div class="error">TfL status unavailable<div class="sub">${esc(t.error)}</div></div>`;
  } else {
    const f = t.featured;
    const featured = f ? `
      <section class="feat ${f.disrupted ? "bad" : ""}">
        <div class="feat-top">
          <span class="swatch big" style="background:${COLOURS[f.id] ?? "#000"}"></span>
          <span class="feat-name">${esc(lineName(f))}</span>
        </div>
        <div class="feat-status">${esc(f.status)}</div>
        ${f.reasons.length ? `<div class="feat-reason">${esc(f.reasons.join(" "))}</div>` : ""}
      </section>` : "";

    const others = t.lines
      .filter((l) => l !== f)
      .sort((a, b) => (b.disrupted - a.disrupted) || (a.disrupted && b.disrupted ? a.severity - b.severity : 0));
    const grid = others.map((l) => `
      <div class="cell ${l.disrupted ? "bad" : ""}">
        <span class="swatch" style="background:${COLOURS[l.id] ?? "#888"}"></span>
        <span class="name">${esc(l.name)}</span>
        <span class="status">${esc(l.status)}</span>
      </div>`).join("");

    const disruptedCount = t.lines.filter((l) => l.disrupted).length;

    body = `${featured}
      <div class="section-title"><span>All Lines</span>
        <span class="sub">${disruptedCount ? `${disruptedCount} with disruption` : "Good service on all lines"}</span></div>
      <div class="grid">${grid}</div>`;
  }

  return `<!doctype html><html><head><meta charset="utf-8"><style>
  ${frameCss(width, height)}
  .feat { margin-top:30px; border:5px solid #000; border-radius:22px; padding:26px 32px 28px; }
  .feat.bad { background:#000; color:#fff; }
  .feat-top { display:flex; align-items:center; gap:18px; }
  .feat-name { font-size:40px; font-weight:800; text-transform:uppercase; letter-spacing:2px; }
  .feat-status { font-size:88px; font-weight:800; line-height:1; margin:18px 0 6px; letter-spacing:-2px; }
  .feat-reason { font-size:29px; font-weight:500; line-height:1.3; margin-top:14px;
    display:-webkit-box; -webkit-line-clamp:5; -webkit-box-orient:vertical; overflow:hidden; }

  .swatch { width:14px; height:40px; border:3px solid #000; border-radius:4px; flex:none; }
  .swatch.big { width:22px; height:50px; }
  .feat.bad .swatch, .cell.bad .swatch { border-color:#fff; }

  .section-title { display:flex; justify-content:space-between; align-items:baseline;
    font-size:30px; font-weight:800; text-transform:uppercase; letter-spacing:2px; padding:30px 0 16px; }
  .section-title .sub { font-size:26px; font-weight:600; text-transform:none; letter-spacing:0; }

  .grid { display:grid; grid-template-columns:1fr 1fr; gap:10px 16px; }
  .cell { display:flex; align-items:center; gap:14px; height:60px; padding:0 16px;
    border:3px solid #000; border-radius:12px; }
  .cell.bad { background:#000; color:#fff; }
  .cell .name { font-size:28px; font-weight:800; white-space:nowrap; }
  .cell .status { margin-left:auto; font-size:21px; font-weight:600; text-align:right;
    white-space:nowrap; overflow:hidden; text-overflow:ellipsis; max-width:230px; }

  .error { margin:auto; text-align:center; font-size:56px; font-weight:800; }
  .error .sub { font-size:26px; font-weight:500; margin-top:16px; }

  </style></head><body><div class="page">
    ${pageHeader("TfL Status", dateStr)}
    ${body}
    ${pageFooter(updated, "Weather")}
  </div></body></html>`;
}
