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

  /* Footer with the Home button. The Kindle exits to its home screen when this
     button is tapped (its position is published as home.txt by render.mjs). */
  .frame-footer { display:flex; justify-content:space-between; align-items:center;
    margin-top:auto; padding-top:20px; border-top:2px solid #000; font-size:26px; font-weight:600; }
  .home { display:flex; align-items:center; gap:14px; height:78px; padding:0 30px 0 24px; flex:none;
    background:#000; color:#fff; border-radius:16px; font-size:31px; font-weight:800; }
  `;
}

export function pageHeader(title, dateStr) {
  return `<header class="rule">
      <div class="loc">${title}</div>
      <div class="date">${dateStr}</div>
      <div class="clock" id="clock"></div>
    </header>`;
}

const HOUSE = `<svg width="40" height="40" viewBox="0 0 40 40" xmlns="http://www.w3.org/2000/svg">
  <path d="M5 19 L20 6 L35 19" fill="none" stroke="#fff" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M10 17 V34 H30 V17" fill="none" stroke="#fff" stroke-width="4.5" stroke-linejoin="round"/>
  <rect x="17" y="24" width="6" height="10" fill="#fff"/></svg>`;

export function pageFooter(leftText) {
  return `<footer class="frame-footer">
      <div>${leftText}</div>
      <div class="home" id="home">${HOUSE}<span>Kindle Home</span></div>
    </footer>`;
}
