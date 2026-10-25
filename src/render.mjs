// Orchestrates: load config -> fetch data -> build HTML -> screenshot (Playwright)
// -> convert to exact-size 8-bit grayscale PNG (sharp).
// Output: public/dashboard.png (weather), public/tfl.png (TfL status),
//         public/clock.txt, home.txt, next.txt, refresh.txt ("top left width height"
//         of the header clock box and the footer buttons, used by the Kindle) and
//         public/stamp.txt (when this render ran; the Kindle watches it after a refresh).
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { chromium } from "playwright";
import sharp from "sharp";
import { fetchData } from "./data.mjs";
import { buildHtml } from "./ui.mjs";
import { fetchTfl } from "./data-tfl.mjs";
import { buildTflHtml } from "./ui-tfl.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const keepHtml = process.argv.includes("--keep-html");

async function main() {
  const config = JSON.parse(await readFile(join(root, "config.json"), "utf8"));
  const { width, height } = config.display;
  const out = join(root, "public");
  await mkdir(out, { recursive: true });

  console.log(`Fetching weather for ${config.location.name} (${config.location.latitude}, ${config.location.longitude})...`);
  const weather = await fetchData(config);
  console.log(`  now ${weather.current.temp}${weather.tempUnit} ${weather.current.label}, AQI ${weather.air.aqi}, UV ${weather.today.uv}`);

  console.log("Fetching TfL line status...");
  const tfl = await fetchTfl(config);
  if (tfl.error) console.log(`  TfL unavailable: ${tfl.error}`);
  else console.log(`  ${tfl.lines.length} lines, featured ${tfl.featured?.name}: ${tfl.featured?.status}`);

  const screens = [
    { file: "dashboard", html: buildHtml(weather, { width, height }) },
    { file: "tfl", html: buildTflHtml(tfl, { width, height }) },
  ];

  const browser = await chromium.launch({ args: ["--no-sandbox", "--force-color-profile=srgb"] });
  const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
  const boxes = { clock: [], home: [], next: [], refresh: [] };
  for (const s of screens) {
    if (keepHtml) await writeFile(join(out, `${s.file}.html`), s.html);
    await page.setContent(s.html, { waitUntil: "networkidle" });
    for (const id of Object.keys(boxes)) {
      boxes[id].push(await page.$eval(`#${id}`, (el) => {
        const r = el.getBoundingClientRect();
        return [r.top, r.left, r.width, r.height].map(Math.round).join(" ");
      }));
    }
    const raw = await page.screenshot({ clip: { x: 0, y: 0, width, height } });

    // Convert to exact-size, 8-bit single-channel grayscale PNG for the Kindle.
    await sharp(raw)
      .resize(width, height, { fit: "fill" })
      .grayscale()
      .toColourspace("b-w")
      .png({ compressionLevel: 9, effort: 10, palette: false })
      .toFile(join(out, `${s.file}.png`));
    console.log(`Wrote public/${s.file}.png`);
  }
  await browser.close();

  // The Kindle draws the clock into, and takes Home taps from, these boxes,
  // so each must be in the same place on every screen.
  for (const [id, list] of Object.entries(boxes)) {
    if (new Set(list).size !== 1) throw new Error(`#${id} differs between screens: ${list.join(" / ")}`);
    await writeFile(join(out, `${id}.txt`), list[0] + "\n");
    console.log(`${id} box (top left width height): ${list[0]}`);
  }

  await writeFile(join(out, "stamp.txt"), `${Date.now()}\n`);

  // Minimal landing page for GitHub Pages (also lets you eyeball both screens in a browser).
  const t = Date.now();
  await writeFile(join(out, "index.html"),
    `<!doctype html><title>Kindle Dashboard</title><meta http-equiv="refresh" content="60">` +
    `<body style="margin:0;background:#444;text-align:center">` +
    screens.map((s) => `<img src="${s.file}.png?t=${t}" style="max-height:100vh;margin:10px;box-shadow:0 0 30px #000">`).join(""));
}

main().catch((e) => { console.error(e); process.exit(1); });
