// Shared page frame for every dashboard screen: base CSS plus the header row.
// The header's clock box must sit at the same spot on every screen, because the
// Kindle draws a live clock into it (render.mjs checks this on every build).

export function frameCss(width, height) {
  return `
  * { margin:0; padding:0; box-sizing:border-box; }
  html,body { width:${width}px; height:${height}px; background:#fff; color:#000;
    font-family: "Helvetica Neue", Arial, "Liberation Sans", sans-serif;
    -webkit-font-smoothing: none; }
  .page { width:${width}px; height:${height}px; padding:46px 50px; display:flex; flex-direction:column; }
  .rule { border-bottom:4px solid #000; }
  .rule-thin { border-bottom:2px solid #000; }

  header { display:flex; justify-content:space-between; align-items:baseline; padding-bottom:18px; }
  header .loc { font-size:62px; font-weight:800; letter-spacing:-1px; }
  header .date { font-size:30px; font-weight:600; margin-left:auto; margin-right:36px; }
  /* Left blank on purpose: the Kindle draws a live clock into this box (see kindle/weather-dash.sh). */
  header .clock { width:190px; height:62px; flex:none; }
  `;
}

export function pageHeader(title, dateStr) {
  return `<header class="rule">
      <div class="loc">${title}</div>
      <div class="date">${dateStr}</div>
      <div class="clock" id="clock"></div>
    </header>`;
}
