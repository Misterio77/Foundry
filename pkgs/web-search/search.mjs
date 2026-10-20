const browserUserAgent =
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36";

// Use the subscription session, not Kagi's metered Search API.
export async function searchKagi(token, query, count, fetchImpl = fetch) {
  const url = new URL("https://kagi.com/html/search");
  url.search = new URLSearchParams({ q: query }).toString();
  const response = await fetchImpl(url, {
    headers: {
      Cookie: `kagi_session=${token}`,
      "User-Agent": browserUserAgent,
    },
    redirect: "manual",
    signal: AbortSignal.timeout(30_000),
  });
  if ([301, 302, 303, 307, 308, 401, 403].includes(response.status)) {
    throw new Error("Kagi rejected the session; renew your session-token file");
  }
  if (!response.ok) throw new Error(`Kagi returned HTTP ${response.status}`);
  return parseKagiHtml(await response.text(), count);
}

// Parse Kagi's /html/search markup into results. Mirrors the selectors kagi-ken
// relies on (`.search-result` / grouped `.__srgi`, with `.__sri_title_link` /
// `.__srgi-title a` titles and `.__sri-desc` snippets), but with regexes to stay
// dependency-free. Fragile by nature: if Kagi reshuffles its HTML this returns
// fewer/no results rather than crashing.
export function parseKagiHtml(html, count) {
  const results = [];
  const chunks = html.split(
    /<div\b[^>]*class=["'][^"']*(?:search-result|__srgi(?=["'\s]))/i,
  );
  for (const chunk of chunks.slice(1)) {
    if (results.length >= count) break;
    let link = extractAnchor(chunk, /__sri_title_link/i);
    if (!link) {
      const idx = chunk.search(/__srgi-title/i);
      if (idx >= 0) link = extractAnchor(chunk.slice(idx), /href=/i);
    }
    if (!link) continue;
    const snippet = chunk.match(
      /class=["'][^"']*__sri-desc[^"']*["'][^>]*>([\s\S]*?)<\/(?:div|span|p)>/i,
    )?.[1];
    results.push({
      title: link.title,
      url: link.url,
      snippet: snippet ? stripTags(snippet) : "",
    });
  }
  return results;
}

// Find the first <a> whose attributes match `attrRe` and that carries a usable
// href, returning its href + plain-text title.
function extractAnchor(html, attrRe) {
  for (const [, attrs, content] of html.matchAll(
    /<a\b([^>]*)>([\s\S]*?)<\/a>/gi,
  )) {
    if (!attrRe.test(attrs)) continue;
    const href = attrs.match(/href=["']([^"']*)["']/i)?.[1];
    if (!href || href.startsWith("#")) continue;
    const title = stripTags(content);
    if (!title) continue;
    return { url: stripTags(href), title };
  }
  return null;
}

// Kagi snippets may carry inline highlight tags (<b>, <em>).
// Strip them and decode the handful of entities that show up in those short
// strings.
function stripTags(html) {
  return html
    .replace(/<[^>]+>/g, "")
    .replace(/&#x([0-9a-f]+);/gi, (_m, hex) =>
      safeFromCodePoint(parseInt(hex, 16)),
    )
    .replace(/&#(\d+);/g, (_m, dec) => safeFromCodePoint(parseInt(dec, 10)))
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function safeFromCodePoint(code) {
  try {
    return String.fromCodePoint(code);
  } catch {
    return "";
  }
}
