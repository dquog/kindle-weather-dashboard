// Fetches weather + air-quality data from Open-Meteo (free, no API key)
// and computes moon phase locally. Returns a normalized object for the UI.

const WMO = {
  0:  ["Clear sky", "clear"],
  1:  ["Mainly clear", "clear"],
  2:  ["Partly cloudy", "partly"],
  3:  ["Overcast", "cloudy"],
  45: ["Fog", "fog"],
  48: ["Rime fog", "fog"],
  51: ["Light drizzle", "drizzle"],
  53: ["Drizzle", "drizzle"],
  55: ["Heavy drizzle", "drizzle"],
  56: ["Freezing drizzle", "drizzle"],
  57: ["Freezing drizzle", "drizzle"],
  61: ["Light rain", "rain"],
  63: ["Rain", "rain"],
  65: ["Heavy rain", "rain"],
  66: ["Freezing rain", "rain"],
  67: ["Freezing rain", "rain"],
  71: ["Light snow", "snow"],
  73: ["Snow", "snow"],
  75: ["Heavy snow", "snow"],
  77: ["Snow grains", "snow"],
  80: ["Rain showers", "rain"],
  81: ["Rain showers", "rain"],
  82: ["Violent showers", "rain"],
  85: ["Snow showers", "snow"],
  86: ["Snow showers", "snow"],
  95: ["Thunderstorm", "storm"],
  96: ["Thunderstorm, hail", "storm"],
  99: ["Thunderstorm, hail", "storm"],
};

export function describeCode(code) {
  const [label, icon] = WMO[code] ?? ["—", "cloudy"];
  return { label, icon };
}

// Moon phase: fraction 0..1 (0 = new, 0.5 = full). Uses a known new moon epoch.
export function moonPhase(date = new Date()) {
  const synodic = 29.53058867;
  const knownNew = Date.UTC(2000, 0, 6, 18, 14); // 2000-01-06 18:14 UTC
  const days = (date.getTime() - knownNew) / 86400000;
  let frac = (days % synodic) / synodic;
  if (frac < 0) frac += 1;
  const names = [
    "New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
    "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent",
  ];
  const idx = Math.floor((frac * 8 + 0.5)) % 8;
  // illuminated fraction (0..1)
  const illum = (1 - Math.cos(2 * Math.PI * frac)) / 2;
  return { frac, name: names[idx], illumination: illum };
}

function aqiLabel(aqi) {
  if (aqi == null) return "—";
  if (aqi <= 50) return "Good";
  if (aqi <= 100) return "Moderate";
  if (aqi <= 150) return "Unhealthy (SG)";
  if (aqi <= 200) return "Unhealthy";
  if (aqi <= 300) return "Very Unhealthy";
  return "Hazardous";
}

function uvLabel(uv) {
  if (uv == null) return "—";
  if (uv < 3) return "Low";
  if (uv < 6) return "Moderate";
  if (uv < 8) return "High";
  if (uv < 11) return "Very High";
  return "Extreme";
}

export async function fetchData(config) {
  const { latitude, longitude, timezone } = config.location;
  const tUnit = config.units.temperature;
  const wUnit = config.units.wind;

  const fUrl = new URL("https://api.open-meteo.com/v1/forecast");
  fUrl.search = new URLSearchParams({
    latitude, longitude, timezone,
    temperature_unit: tUnit,
    wind_speed_unit: wUnit,
    precipitation_unit: config.units.precipitation,
    current: "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m,wind_direction_10m",
    hourly: "temperature_2m,precipitation,precipitation_probability,weather_code",
    daily: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,precipitation_sum",
    forecast_days: "2",
  }).toString();

  const aUrl = new URL("https://air-quality-api.open-meteo.com/v1/air-quality");
  aUrl.search = new URLSearchParams({
    latitude, longitude, timezone,
    current: "us_aqi,pm2_5",
  }).toString();

  const [fRes, aRes] = await Promise.all([
    fetch(fUrl).then((r) => r.json()),
    fetch(aUrl).then((r) => r.json()).catch(() => null),
  ]);

  const now = new Date();
  // index of the current hour within the hourly arrays
  const hours = fRes.hourly.time;
  let startIdx = hours.findIndex((t) => new Date(t) >= now);
  if (startIdx < 0) startIdx = 0;
  if (startIdx > 0) startIdx -= 1; // include current hour

  const next12 = [];
  for (let i = startIdx; i < startIdx + 12 && i < hours.length; i++) {
    next12.push({
      time: hours[i],
      hour: new Date(hours[i]).getHours(),
      temp: fRes.hourly.temperature_2m[i],
      precip: fRes.hourly.precipitation[i] ?? 0,
      pop: fRes.hourly.precipitation_probability?.[i] ?? 0,
    });
  }

  const cur = fRes.current;
  const curDesc = describeCode(cur.weather_code);

  return {
    generatedAt: now,
    tempUnit: tUnit === "fahrenheit" ? "°F" : "°C",
    windUnit: wUnit,
    location: config.location.name,
    current: {
      temp: Math.round(cur.temperature_2m),
      feels: Math.round(cur.apparent_temperature),
      humidity: cur.relative_humidity_2m,
      wind: Math.round(cur.wind_speed_10m),
      windDir: cur.wind_direction_10m,
      isDay: cur.is_day === 1,
      label: curDesc.label,
      icon: curDesc.icon,
    },
    today: {
      hi: Math.round(fRes.daily.temperature_2m_max[0]),
      lo: Math.round(fRes.daily.temperature_2m_min[0]),
      sunrise: fRes.daily.sunrise[0],
      sunset: fRes.daily.sunset[0],
      uv: Math.round(fRes.daily.uv_index_max[0]),
      uvLabel: uvLabel(fRes.daily.uv_index_max[0]),
      precipSum: fRes.daily.precipitation_sum[0],
    },
    hourly: next12,
    air: {
      aqi: aRes?.current?.us_aqi ?? null,
      aqiLabel: aqiLabel(aRes?.current?.us_aqi),
      pm25: aRes?.current?.pm2_5 ?? null,
    },
    moon: moonPhase(now),
  };
}
