// Builds the BBC News screen: the top stories, numbered. Same frame as the others.
import { frameCss, pageHeader, pageFooter, updatedStamp } from "./frame.mjs";

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

function ago(date, now) {
  const mins = Math.round((now - date) / 60000);
  if (!Number.isFinite(mins)) return "";
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins} min ago`;
  const hrs = Math.round(mins / 60);
  return hrs < 24 ? `${hrs} hour${hrs === 1 ? "" : "s"} ago` : `${Math.round(hrs / 24)} days ago`;
}

export function buildNewsHtml(n, { width, height }, nextLabel) {
  const dateStr = n.generatedAt.toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long" });
  const body = n.error
    ? `<div class="error">BBC News unavailable<div class="sub">${esc(n.error)}</div></div>`
    : `<ol class="stories">${n.items.map((s, i) => `
        <li class="story">
          <div class="num">${i + 1}</div>
          <div class="text">
            <div class="title">${esc(s.title)}</div>
            ${s.summary ? `<div class="summary">${esc(s.summary)}</div>` : ""}
            <div class="meta">${ago(s.published, n.generatedAt)}</div>
          </div>
        </li>`).join("")}
      </ol>`;

  return `<!doctype html><html><head><meta charset="utf-8"><style>
  ${frameCss(width, height)}
  .stories { list-style:none; flex:1; display:flex; flex-direction:column; padding-top:10px; min-height:0; }
  .story { flex:1; display:flex; gap:24px; align-items:flex-start; padding:20px 0;
    border-bottom:2px solid #000; min-height:0; overflow:hidden; }
  .story:last-child { border-bottom:none; }
  .num { flex:none; width:64px; height:64px; border-radius:14px; background:#000; color:#fff;
    font-size:40px; font-weight:800; display:flex; align-items:center; justify-content:center; }
  .text { min-width:0; }
  .title { font-size:38px; font-weight:800; line-height:1.15; letter-spacing:-0.5px;
    display:-webkit-box; -webkit-line-clamp:2; -webkit-box-orient:vertical; overflow:hidden; }
  .summary { font-size:25px; font-weight:500; line-height:1.3; margin-top:8px;
    display:-webkit-box; -webkit-line-clamp:2; -webkit-box-orient:vertical; overflow:hidden; }
  .meta { font-size:21px; font-weight:700; margin-top:8px; text-transform:uppercase; letter-spacing:1px; }
  .error { margin:auto; text-align:center; font-size:56px; font-weight:800; }
  .error .sub { font-size:26px; font-weight:500; margin-top:16px; }
  </style></head><body><div class="page">
    ${pageHeader("BBC News", dateStr)}
    ${body}
    ${pageFooter(updatedStamp(n.generatedAt), nextLabel)}
  </div></body></html>`;
}
