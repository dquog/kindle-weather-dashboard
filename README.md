# Kindle Weather Dashboard (serverless)

A minimalist e-ink weather station for a **jailbroken Kindle Paperwhite 7th gen**
(1072 × 1448, 8-bit grayscale). No Raspberry Pi, no always-on computer.

**How it works**

```
GitHub Actions (every 30 min)          Your Kindle (WinterBreak + FBInk)
┌─────────────────────────────┐        ┌──────────────────────────────┐
│ fetch Open-Meteo data        │        │ loop:                        │
│ render HTML → screenshot      │  PNG   │   curl the PNG from the URL  │
│ convert → 1072×1448 gray PNG │ ─────▶ │   fbink draws it full-screen │
│ publish to GitHub Pages      │  URL   │   sleep 30 min, repeat       │
└─────────────────────────────┘        └──────────────────────────────┘
```

GitHub renders the image for free on a schedule and serves it at a fixed URL.
The Kindle just downloads that URL and paints it. That's the whole system.

Weather data comes from [Open-Meteo](https://open-meteo.com) — free, **no API key**.

---

## 1. Set your location

Edit [`config.json`](config.json): put in your `latitude`, `longitude`, `name`,
and switch `temperature` to `fahrenheit` / `wind` to `mph` if you prefer.
(Find coordinates at e.g. latlong.net.)

## 2. Preview locally (optional)

```bash
npm install
npx playwright install chromium
npm run render      # writes public/dashboard.png — open it to check the look
```

## 3. Push to GitHub

Create a **public** repo (public repos get free Pages). With the GitHub CLI:

```bash
cd ~/kindle-weather-dashboard
git add -A
git commit -m "Kindle weather dashboard"
gh repo create kindle-weather-dashboard --public --source=. --push
```

Then in the repo on github.com: **Settings → Pages → Build and deployment →
Source: GitHub Actions**. Next, open the **Actions** tab → *Update dashboard* →
**Run workflow** (the scheduled runs start automatically after this first one).

Your image is now live at:

```
https://<your-username>.github.io/kindle-weather-dashboard/dashboard.png
```

Open it in a browser to confirm before touching the Kindle.

## 4. Set up the Kindle

1. Open [`kindle/weather-dash.sh`](kindle/weather-dash.sh) and set `URL=` to the
   `dashboard.png` link from step 3.
2. Copy the `dashboard/` folder (containing `weather-dash.sh`) to the Kindle's USB
   storage — it has already been staged there for you at `/mnt/us/dashboard/`.
3. On the Kindle, open **kterm** (install via `kpm install kterm` if needed) and run:

   ```sh
   sh /mnt/us/dashboard/weather-dash.sh
   ```

The screen flashes once, then shows the dashboard and refreshes every 30 minutes.
Keep it **plugged in** for an always-on wall/desk display.

---

## Tuning

| What | Where | Notes |
|------|-------|-------|
| Refresh interval | `INTERVAL` in `weather-dash.sh` | seconds; 1800 = 30 min |
| Anti-ghosting flash | `FULL_EVERY` in `weather-dash.sh` | full refresh every Nth update |
| Render schedule | `cron` in `.github/workflows/update-dashboard.yml` | keep it ≥ the device interval |
| Screen size | `display` in `config.json` | PW5=1236×1648, Scribe=1860×2480 |
| Data shown | `src/ui.mjs` (layout) + `src/data.mjs` (fetch) | |

## Good to know

- **GitHub cron isn't exact** — scheduled runs can be delayed 5–15 min or skipped
  under load. Fine for weather; don't expect to-the-minute updates.
- **Scheduled workflows auto-disable after 60 days** of no repo commits. Push any
  commit (or click *Run workflow*) to re-arm them.
- **Battery vs. plugged in** — this loop keeps the device awake, so run it on power.
  For battery use, switch to an `rtcwake`-based suspend-between-refreshes approach.
- **Private repo?** GitHub Pages on private repos needs a paid plan. Use a public
  repo (the data is just public weather) or publish the PNG another way.
