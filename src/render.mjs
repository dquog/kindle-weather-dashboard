// Orchestrates: load config -> fetch data -> build HTML -> screenshot (Playwright)
// -> convert to exact-size 8-bit grayscale PNG (sharp). Output: public/dashboard.png
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { chromium } from "playwright";
import sharp from "sharp";
import { fetchData } from "./data.mjs";
import { buildHtml } from "./ui.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const keepHtml = process.argv.includes("--keep-html");

async function main() {
  const config = JSON.parse(await readFile(join(root, "config.json"), "utf8"));
  const { width, height } = config.display;

  console.log(`Fetching weather for ${config.location.name} (${config.location.latitude}, ${config.location.longitude})...`);
  const data = await fetchData(config);
  console.log(`  now ${data.current.temp}${data.tempUnit} ${data.current.label}, AQI ${data.air.aqi}, UV ${data.today.uv}`);

  const html = buildHtml(data, { width, height });
  await mkdir(join(root, "public"), { recursive: true });
  if (keepHtml) await writeFile(join(root, "public", "preview.html"), html);

  const browser = await chromium.launch({ args: ["--no-sandbox", "--force-color-profile=srgb"] });
  const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
  await page.setContent(html, { waitUntil: "networkidle" });
  const raw = await page.screenshot({ clip: { x: 0, y: 0, width, height } });
  await browser.close();

  // Convert to exact-size, 8-bit single-channel grayscale PNG for the Kindle.
  await sharp(raw)
    .resize(width, height, { fit: "fill" })
    .grayscale()
    .toColourspace("b-w")
    .png({ compressionLevel: 9, effort: 10, palette: false })
    .toFile(join(root, "public", "dashboard.png"));

  // Minimal landing page for GitHub Pages (also lets you eyeball it in a browser).
  await writeFile(join(root, "public", "index.html"),
    `<!doctype html><title>Kindle Weather</title><meta http-equiv="refresh" content="60">` +
    `<body style="margin:0;background:#444;text-align:center">` +
    `<img src="dashboard.png?t=${Date.now()}" style="max-height:100vh;box-shadow:0 0 30px #000">`);

  console.log("Wrote public/dashboard.png");
}

main().catch((e) => { console.error(e); process.exit(1); });
