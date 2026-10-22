// Bold, high-contrast SVG weather icons tuned for grayscale e-ink.
// All strokes pure black (#000) on transparent; sized by the container.

const S = 'stroke="#000" fill="none" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"';
const FILL = 'fill="#000"';

const sun = `<circle cx="50" cy="50" r="22" ${S}/>` +
  Array.from({ length: 8 }, (_, i) => {
    const a = (i * Math.PI) / 4;
    const x1 = 50 + Math.cos(a) * 32, y1 = 50 + Math.sin(a) * 32;
    const x2 = 50 + Math.cos(a) * 44, y2 = 50 + Math.sin(a) * 44;
    return `<line x1="${x1.toFixed(1)}" y1="${y1.toFixed(1)}" x2="${x2.toFixed(1)}" y2="${y2.toFixed(1)}" ${S}/>`;
  }).join("");

const cloud = `<path d="M28 70 Q12 70 12 54 Q12 40 28 40 Q32 22 52 24 Q72 24 74 44 Q90 44 90 58 Q90 70 76 70 Z" ${S}/>`;

const cloudFilled = `<path d="M28 70 Q12 70 12 54 Q12 40 28 40 Q32 22 52 24 Q72 24 74 44 Q90 44 90 58 Q90 70 76 70 Z" fill="#000" stroke="#000" stroke-width="2"/>`;

function drops(n) {
  const xs = n === 3 ? [32, 52, 72] : n === 2 ? [40, 64] : [52];
  return xs.map((x) => `<line x1="${x}" y1="74" x2="${x - 6}" y2="92" ${S}/>`).join("");
}

function flakes(n) {
  const xs = n === 3 ? [32, 52, 72] : [40, 64];
  return xs.map((x) => `<circle cx="${x}" cy="84" r="3.5" ${FILL}/>`).join("");
}

const ICONS = {
  clear: sun,
  partly: `<g transform="translate(-6,-10) scale(0.7)">${sun}</g>${cloud}`,
  cloudy: cloud,
  fog: `${cloud}<line x1="20" y1="82" x2="80" y2="82" ${S}/><line x1="28" y1="92" x2="72" y2="92" ${S}/>`,
  drizzle: `${cloud}${drops(2)}`,
  rain: `${cloud}${drops(3)}`,
  snow: `${cloud}${flakes(3)}`,
  storm: `${cloud}<polygon points="52,72 40,94 50,94 44,110 68,86 56,86 64,72" ${FILL}/>`,
};

export function weatherIcon(name, size = 100) {
  const body = ICONS[name] ?? ICONS.cloudy;
  return `<svg viewBox="0 0 100 110" width="${size}" height="${size * 1.1}" xmlns="http://www.w3.org/2000/svg">${body}</svg>`;
}

// Moon rendered by illuminated fraction (frac 0..1 of the synodic cycle).
// Base disc is dark; the lit area is painted white, bounded by the outer limb
// and the terminator ellipse. Northern-hemisphere orientation (waxing = lit right).
export function moonIcon(frac, size = 70) {
  const r = 42, cx = 50, cy = 50;
  const f = (1 - Math.cos(2 * Math.PI * frac)) / 2; // illumination 0..1
  const waxing = frac < 0.5;
  const outline = `<circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="#000" stroke-width="3"/>`;
  const dark = `<circle cx="${cx}" cy="${cy}" r="${r}" fill="#000"/>`;
  const svg = (inner) =>
    `<svg viewBox="0 0 100 100" width="${size}" height="${size}" xmlns="http://www.w3.org/2000/svg">${inner}</svg>`;

  if (f <= 0.02) return svg(dark + outline);                                   // new
  if (f >= 0.98) return svg(`<circle cx="${cx}" cy="${cy}" r="${r}" fill="#fff"/>` + outline); // full

  const rx = r * Math.abs(1 - 2 * f);
  const outerSweep = waxing ? 1 : 0;
  const innerSweep = f > 0.5 ? outerSweep : 1 - outerSweep;
  const lit = `<path d="M${cx} ${cy - r} A ${r} ${r} 0 0 ${outerSweep} ${cx} ${cy + r} ` +
    `A ${rx.toFixed(2)} ${r} 0 0 ${innerSweep} ${cx} ${cy - r} Z" fill="#fff"/>`;
  return svg(dark + lit + outline);
}
