# Kindle Dashboard (serverless)

A minimalist e-ink dashboard for a **jailbroken Kindle Paperwhite 7th gen**
(1072 × 1448, 8-bit grayscale). Two screens it cycles between:

- **Weather** — Old Street, London: temperature, 12-hour rain chance, temperature
  line, air quality, UV, sunrise/sunset, moon. Data from [Open-Meteo](https://open-meteo.com).
- **TfL Status** — the Northern line featured at the top, plus every Tube,
  Elizabeth line, Overground and DLR line. Data from the [TfL API](https://api.tfl.gov.uk).

The Kindle draws a **live clock** into the header of both screens every minute,
and both screens share a **Kindle Home** button that exits the dashboard.

No Raspberry Pi, no always-on computer.

```
GitHub Actions                              Kindle (WinterBreak + FBInk)
┌────────────────────────────────┐          ┌───────────────────────────────────┐
│ fetch Open-Meteo + TfL data    │   PNGs   │ every 2 min: switch screen        │
│ render HTML → screenshot       │ ───────▶ │ every minute: redraw the clock    │
│ dashboard.png, tfl.png,        │          │ every 15 min: ask GitHub to       │
│ clock.txt → GitHub Pages       │ ◀─────── │   re-render (if token present)    │
└────────────────────────────────┘ trigger  └───────────────────────────────────┘
```

## Layout

| Path | What |
|------|------|
| `config.json` | location, units, screen size, TfL featured line |
| `src/render.mjs` | renders both screens + `clock.txt` |
| `src/data.mjs`, `src/ui.mjs` | weather screen |
| `src/data-tfl.mjs`, `src/ui-tfl.mjs` | TfL screen |
| `src/frame.mjs` | shared header (incl. the clock box) |
| `kindle/weather-dash.sh` | the on-device loop → `/mnt/us/dashboard/` |
| `kindle/scriptlets/*.sh` | library tiles → `/mnt/us/documents/` |
| `kindle/touchwatch.lua` | touchscreen grab + Home-tap detection → `/mnt/us/dashboard/` |
| `kindle/fonts/` | clock font (Noto Sans Bold, OFL) → `/mnt/us/dashboard/fonts/` |

## Using it on the Kindle

Tap **Weather Dashboard** in the library. The stock Kindle UI is frozen (as
KOReader does it: touchscreen grabbed, window manager paused) and the dashboard
takes over. **Tap the "Kindle Home" button** (bottom-right) to go straight back to
the library; taps anywhere else are ignored and it never times out. The touch
grab uses KOReader's LuaJIT and `kindle/touchwatch.lua`; without KOReader it falls
back to fully stopping the UI, which makes coming back a slow restart.
Plugging the Kindle into a computer also hands the screen back, and holding the
power button ~40s to restart always works. A log is written to
`dashboard/weatherdash.log` (including where each tap landed).

## Keeping it fresh: the GitHub token (recommended)

GitHub's own timer (`cron` in the workflow) is best-effort and in practice can
skip hours. With a token, the Kindle asks GitHub for a fresh render every
15 minutes instead.

1. github.com → Settings → Developer settings → **Fine-grained tokens** →
   Generate new token.
2. Repository access: **Only select repositories** → `kindle-weather-dashboard`.
3. Permissions → Repository → **Actions: Read and write**. Nothing else.
4. Pick an expiry (e.g. 1 year), generate, copy the token.
5. With the Kindle plugged in, create `dashboard/github-token.txt` on it and
   paste the token in as the only line.

Worst case if the Kindle is lost: someone could trigger or cancel runs of this
one public repo's workflow. Revoke the token on GitHub if that happens.

## Tuning

| What | Where |
|------|-------|
| Seconds per screen / trigger interval / anti-ghosting flash | top of `kindle/weather-dash.sh` |
| Clock size and position | `CLOCK_PX`, `CLOCK_NUDGE` in `weather-dash.sh`; box in `src/frame.mjs` |
| Featured line / which modes | `tfl` in `config.json` |
| Location / units | `location`, `units` in `config.json` |

## Local preview

```bash
npm install
npx playwright install chromium
TZ=Europe/London npm run render   # writes public/dashboard.png and public/tfl.png
```
