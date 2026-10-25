// Builds the dashboard HTML string from normalized data.
// Designed for 1072x1448 portrait, pure black/white for e-ink.
import { weatherIcon, moonIcon } from "./icons.mjs";
import { frameCss, pageHeader, pageFooter, updatedStamp } from "./frame.mjs";

function fmtTime(iso) {
  const d = new Date(iso);
  return d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}
function fmtHour(h) {
  const am = h < 12;
  let hr = h % 12; if (hr === 0) hr = 12;
  return `${hr}${am ? "a" : "p"}`;
}

export function buildHtml(d, { width, height }) {
  const maxPop = Math.max(10, ...d.hourly.map((h) => h.pop));
  const bars = d.hourly.map((h) => {
    const ht = Math.round((h.pop / maxPop) * 150);
    const wet = h.precip >= 0.1;
    return `<div class="bar-col">
      <div class="bar-val">${h.pop >= 5 ? h.pop + "%" : ""}</div>
      <div class="bar-track"><div class="bar-fill ${wet ? "wet" : ""}" style="height:${ht}px"></div></div>
      <div class="bar-hr">${fmtHour(h.hour)}</div>
    </div>`;
  }).join("");

  // Hourly temperature sparkline (same 12 hours as the precip graph).
  const temps = d.hourly.map((h) => h.temp);
  const tMin = Math.min(...temps), tMax = Math.max(...temps);
  const span = Math.max(1, tMax - tMin);
  const W = 972, H = 128, padY = 36, padX = 48;
  const pts = temps.map((t, i) => {
    const x = padX + (i / (temps.length - 1)) * (W - padX * 2);
    const y = padY + (1 - (t - tMin) / span) * (H - padY * 2);
    return [x, y];
  });
  const poly = pts.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(" ");
  const dots = pts.map(([x, y], i) =>
    `<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="5" fill="#000"/>` +
    (i === 0 || i === pts.length - 1 || temps[i] === tMax || temps[i] === tMin
      ? `<text x="${x.toFixed(1)}" y="${(y - 16).toFixed(1)}" font-size="26" font-weight="700" text-anchor="middle">${Math.round(temps[i])}°</text>`
      : "")
  ).join("");
  const sparkline = `<svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg">` +
    `<polyline points="${poly}" fill="none" stroke="#000" stroke-width="5" stroke-linejoin="round" stroke-linecap="round"/>${dots}</svg>`;

  const totalRain = d.hourly.reduce((s, h) => s + (h.precip || 0), 0);
  const rainNote = totalRain >= 0.1
    ? `${totalRain.toFixed(1)} mm expected`
    : "No rain expected";

  const dateStr = d.generatedAt.toLocaleDateString("en-GB", {
    weekday: "long", day: "numeric", month: "long",
  });
  const updated = updatedStamp(d.generatedAt);

  return `<!doctype html><html><head><meta charset="utf-8"><style>
  ${frameCss(width, height)}
  .hero { display:flex; align-items:center; justify-content:space-between; padding:34px 0 20px; }
  .hero .temp { font-size:230px; font-weight:800; line-height:0.86; letter-spacing:-6px; }
  .hero .temp sup { font-size:80px; font-weight:700; vertical-align:top; }
  .hero .cond { margin-top:14px; font-size:40px; font-weight:700; }
  .hero .feels { font-size:28px; font-weight:500; margin-top:4px; }
  .hero .icon { text-align:right; }
  .hilo { display:flex; gap:40px; font-size:34px; font-weight:700; padding:6px 0 30px; }
  .hilo .lo { font-weight:500; }

  .section-title { display:flex; justify-content:space-between; align-items:baseline;
    font-size:30px; font-weight:800; text-transform:uppercase; letter-spacing:2px;
    padding:20px 0 14px; }
  .section-title .sub { font-size:26px; font-weight:600; text-transform:none; letter-spacing:0; }

  .graph { display:flex; justify-content:space-between; align-items:flex-end; height:210px; gap:6px; }
  .bar-col { flex:1; display:flex; flex-direction:column; align-items:center; height:100%; justify-content:flex-end; }
  .bar-val { font-size:20px; font-weight:700; height:26px; }
  .bar-track { width:100%; height:152px; display:flex; align-items:flex-end; justify-content:center; }
  .bar-fill { width:70%; background:#000; }
  .bar-fill.wet { background:repeating-linear-gradient(0deg,#000,#000 6px,#fff 6px,#fff 10px); outline:3px solid #000; }
  .bar-hr { font-size:24px; font-weight:600; margin-top:10px; }

  .tiles { display:flex; gap:22px; margin-top:auto; }
  .tile { flex:1; border:4px solid #000; border-radius:18px; padding:18px 18px; text-align:center;
    display:flex; flex-direction:column; align-items:center; justify-content:center; min-height:176px; }
  .tile .k { font-size:24px; font-weight:800; text-transform:uppercase; letter-spacing:2px; }
  .tile .v { font-size:66px; font-weight:800; line-height:1; margin:8px 0 4px; }
  .tile .s { font-size:26px; font-weight:600; }
  .tile .moonwrap { margin:6px 0; }

  </style></head><body><div class="page">

    ${pageHeader(d.location, dateStr)}

    <div class="hero">
      <div>
        <div class="temp">${d.current.temp}<sup>${d.tempUnit}</sup></div>
        <div class="cond">${d.current.label}</div>
        <div class="feels">Feels like ${d.current.feels}${d.tempUnit} · ${d.current.wind} ${d.windUnit} wind</div>
      </div>
      <div class="icon">${weatherIcon(d.current.icon, 230)}</div>
    </div>
    <div class="hilo rule-thin">
      <div class="hi">High ${d.today.hi}${d.tempUnit}</div>
      <div class="lo">Low ${d.today.lo}${d.tempUnit}</div>
      <div class="lo">Humidity ${d.current.humidity}%</div>
    </div>

    <div class="section-title">
      <span>Next 12 Hours</span>
      <span class="sub">${rainNote}</span>
    </div>
    <div class="graph" style="padding-bottom:16px;">${bars}</div>

    <div class="section-title rule-thin" style="padding-top:8px;">
      <span>Temperature</span>
      <span class="sub">${tMin}° to ${tMax}°</span>
    </div>
    <div style="padding:10px 0 4px;">${sparkline}</div>

    <div class="tiles">
      <div class="tile">
        <div class="k">Air Quality</div>
        <div class="v">${d.air.aqi ?? "—"}</div>
        <div class="s">${d.air.aqiLabel}</div>
      </div>
      <div class="tile">
        <div class="k">UV Index</div>
        <div class="v">${d.today.uv ?? "—"}</div>
        <div class="s">${d.today.uvLabel}</div>
      </div>
      <div class="tile">
        <div class="k">Sun</div>
        <div class="v" style="font-size:40px;">${fmtTime(d.today.sunrise)}</div>
        <div class="s">to ${fmtTime(d.today.sunset)}</div>
      </div>
      <div class="tile">
        <div class="k">Moon</div>
        <div class="moonwrap">${moonIcon(d.moon.frac, 76)}</div>
        <div class="s">${d.moon.name}</div>
      </div>
    </div>

    ${pageFooter(updated, "TfL status")}

  </div></body></html>`;
}
