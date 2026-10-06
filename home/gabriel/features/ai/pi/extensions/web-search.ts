import fs from "node:fs";
import path from "node:path";

import {
  getAgentDir,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";

const browserUserAgent =
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36";

type SearchParams = {
  query: string;
  count?: number;
};

type SearchResult = {
  title: string;
  url: string;
  snippet: string;
};

type PiSettings = {
  webSearch?: { kagiSessionTokenFile?: string | null };
};

export default function webSearch(pi: ExtensionAPI) {
  pi.registerTool({
    name: "web_search",
    label: "Web Search",
    description:
      "Search the web and return a ranked list of results (title, URL, snippet). " +
      "To read a result in full, fetch its URL (see the web-fetch skill). " +
      "Uses your Kagi subscription via a configured session token.",
    promptSnippet:
      "web_search: query the web for current information; read a result in full via the web-fetch skill",
    parameters: {
      type: "object",
      properties: {
        query: { type: "string", description: "Search query." },
        count: {
          type: "integer",
          minimum: 1,
          maximum: 20,
          description: "Number of results to return (1-20). Defaults to 8.",
        },
      },
      required: ["query"],
      additionalProperties: false,
    },
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      const p = params as SearchParams;
      const query = p.query.trim();
      if (!query) throw new Error("Empty search query.");
      const count = p.count ?? 8;

      const token = readSessionToken(ctx.cwd);
      if (!token) {
        throw new Error(
          "No Kagi session token configured. Set settings.webSearch.kagiSessionTokenFile " +
            "to the absolute path of your session-token file to use your Kagi subscription.",
        );
      }
      const results = await searchKagi(token, query, count, signal);
      const text = results.length
        ? [
            `Search results for "${query}" (via kagi (session)):`,
            "",
            ...results.map(
              (r, i) =>
                `${i + 1}. ${r.title}\n   ${r.url}${r.snippet ? `\n   ${r.snippet}` : ""}`,
            ),
          ].join("\n")
        : `No results for "${query}".`;
      return {
        content: [{ type: "text", text }],
        details: { backend: "kagi (session)", query, count: results.length },
      };
    },
  });
}

// Use Kagi's lightweight /html/search endpoint with the subscription session
// cookie, not the metered Search API.
async function searchKagi(
  token: string,
  query: string,
  count: number,
  signal?: AbortSignal,
): Promise<SearchResult[]> {
  const url = new URL("https://kagi.com/html/search");
  url.search = new URLSearchParams({ q: query }).toString();
  const timeout = AbortSignal.timeout(30_000);
  const response = await fetch(url, {
    headers: {
      Cookie: `kagi_session=${token}`,
      "User-Agent": browserUserAgent,
    },
    signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
  });
  if (response.status === 401 || response.status === 403) {
    throw new Error("invalid or expired session token");
  }
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return parseKagiHtml(await response.text(), count);
}

function readSessionToken(cwd: string): string | undefined {
  const config = {
    ...readSettings(path.join(getAgentDir(), "settings.json")).webSearch,
    ...readSettings(path.join(cwd, ".pi/settings.json")).webSearch,
  };
  const file = config.kagiSessionTokenFile;
  if (file == null) return undefined;
  if (typeof file !== "string") {
    throw new Error("web_search: kagiSessionTokenFile must be a string");
  }
  if (!file) return undefined;
  if (!path.isAbsolute(file)) {
    throw new Error("web_search: secret file paths must be absolute");
  }
  return fs.readFileSync(file, "utf8").trim() || undefined;
}

function readSettings(file: string): PiSettings {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return {};
    throw err;
  }
}

// Parse Kagi's /html/search markup into results. Mirrors the selectors kagi-ken
// relies on (`.search-result` / grouped `.__srgi`, with `.__sri_title_link` /
// `.__srgi-title a` titles and `.__sri-desc` snippets), but with regexes to stay
// dependency-free. Fragile by nature: if Kagi reshuffles its HTML this returns
// fewer/no results rather than crashing.
function parseKagiHtml(html: string, count: number): SearchResult[] {
  const results: SearchResult[] = [];
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
function extractAnchor(
  html: string,
  attrRe: RegExp,
): { url: string; title: string } | null {
  for (const [, attrs, content] of html.matchAll(
    /<a\b([^>]*)>([\s\S]*?)<\/a>/gi,
  )) {
    if (!attrRe.test(attrs)) continue;
    const href = attrs.match(/href=["']([^"']*)["']/i)?.[1];
    if (!href || href.startsWith("#")) continue;
    const title = stripTags(content);
    if (!title) continue;
    return { url: href, title };
  }
  return null;
}

// Kagi snippets may carry inline highlight tags (<b>, <em>).
// Strip them and decode the handful of entities that show up in those short
// strings.
function stripTags(html: string): string {
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

function safeFromCodePoint(code: number): string {
  try {
    return String.fromCodePoint(code);
  } catch {
    return "";
  }
}
