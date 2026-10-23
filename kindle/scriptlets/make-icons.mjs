// Generates the library cover icons for the two scriptlets (grayscale PNG).
import sharp from "sharp";
const cover = (label, glyph) => `<svg xmlns="http://www.w3.org/2000/svg" width="450" height="600">
  <rect width="450" height="600" fill="#fff"/>
  <rect x="14" y="14" width="422" height="572" rx="28" fill="none" stroke="#000" stroke-width="12"/>
  <g transform="translate(75,90) scale(3)" stroke="#000" stroke-width="7" fill="none" stroke-linecap="round" stroke-linejoin="round">${glyph}</g>
  <text x="225" y="500" font-family="Helvetica, Arial, sans-serif" font-size="58" font-weight="800" text-anchor="middle">${label}</text>
</svg>`;
const cloudRain = `<circle cx="34" cy="30" r="15"/><path d="M28 70 Q12 70 12 54 Q12 40 28 40 Q32 22 52 24 Q72 24 74 44 Q90 44 90 58 Q90 70 76 70 Z" fill="#fff"/><line x1="36" y1="78" x2="30" y2="94"/><line x1="56" y1="78" x2="50" y2="94"/><line x1="76" y1="78" x2="70" y2="94"/>`;
const stop = `<rect x="18" y="14" width="64" height="64" rx="10" fill="#000"/>`;
await sharp(Buffer.from(cover("WEATHER", cloudRain))).flatten({ background: "#fff" }).grayscale().toColourspace("b-w").png({ palette: false }).toFile(new URL("./icon.png", import.meta.url).pathname);
await sharp(Buffer.from(cover("STOP", stop))).flatten({ background: "#fff" }).grayscale().toColourspace("b-w").png({ palette: false }).toFile(new URL("./icon-stop.png", import.meta.url).pathname);
console.log("icons written");
