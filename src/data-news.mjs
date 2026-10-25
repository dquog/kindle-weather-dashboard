// Fetches the BBC News top stories RSS feed and returns the first few items.

const FEED = "https://feeds.bbci.co.uk/news/rss.xml";

const ENTITIES = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" };
function decode(s) {
  return s
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/&(amp|lt|gt|quot|apos);/g, (_, e) => ENTITIES[e])
    .replace(/\s+/g, " ")
    .trim();
}

function tag(item, name) {
  const m = item.match(new RegExp(`<${name}>([\\s\\S]*?)</${name}>`));
  return m ? decode(m[1]) : "";
}

export async function fetchNews(config) {
  const count = config.news?.count ?? 5;
  try {
    const res = await fetch(config.news?.feed ?? FEED);
    if (!res.ok) throw new Error(`BBC feed returned ${res.status}`);
    const xml = await res.text();
    const items = [...xml.matchAll(/<item>([\s\S]*?)<\/item>/g)].slice(0, count).map(([, it]) => ({
      title: tag(it, "title"),
      summary: tag(it, "description"),
      published: new Date(tag(it, "pubDate")),
    }));
    if (!items.length) throw new Error("BBC feed had no stories");
    return { generatedAt: new Date(), items, error: null };
  } catch (e) {
    return { generatedAt: new Date(), items: [], error: e.message };
  }
}
