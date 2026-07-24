import { execFile } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { promisify } from "node:util";

import {
  getAgentDir,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";

const execFileAsync = promisify(execFile);
const AGENT_DIR = getAgentDir();
const GLOBAL_SETTINGS = path.join(AGENT_DIR, "settings.json");
const PROJECT_SETTINGS = path.join(process.cwd(), ".pi/settings.json");

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

type WebSearchConfig = {
  kagiApiKeyFile?: string;
  kagiSessionTokenFile?: string;
  braveApiKeyFile?: string;
};

type PiSettings = { webSearch?: WebSearchConfig };

export default function web(pi: ExtensionAPI) {
  pi.registerTool({
    name: "web_search",
    label: "Web Search",
    description:
      "Search the web and return a ranked list of results (title, URL, snippet). " +
      "To read a result in full, fetch its URL (see the web-fetch skill). " +
      "Requires a configured backend (Kagi API key, Kagi session token, or Brave API key).",
    promptSnippet:
      "web_search: query the web for current information; read a result in full via the web-fetch skill",
    parameters: {
      type: "object",
      properties: {
        query: { type: "string", description: "Search query." },
        count: {
          type: "number",
          description: "Number of results to return (1-20). Defaults to 8.",
        },
      },
      required: ["query"],
      additionalProperties: false,
    },
    async execute(_toolCallId, params) {
      const p = params as SearchParams;
      const query = (p.query ?? "").trim();
      if (!query) return errorResult("Empty search query.");
      const count = clampCount(p.count, 8);

      const backend = await selectBackend();
      if (!backend) {
        return errorResult(
          "No web_search backend configured. Set one of:\n" +
            "  - settings.webSearch.kagiApiKeyFile — Kagi Search API, billed per query\n" +
            "  - settings.webSearch.kagiSessionTokenFile — your Kagi session cookie; rides your subscription, no API key needed\n" +
            "  - settings.webSearch.braveApiKeyFile — Brave Search API, free tier 2k/mo",
        );
      }

      try {
        const results = await backend.search(query, count);
        if (results.length === 0) {
          return {
            content: [{ type: "text", text: `No results for "${query}".` }],
            details: { backend: backend.name, query, count: 0 },
          };
        }
        const text = [
          `Search results for "${query}" (via ${backend.name}):`,
          "",
          ...results.map(
            (r, i) =>
              `${i + 1}. ${r.title}\n   ${r.url}${r.snippet ? `\n   ${r.snippet}` : ""}`,
          ),
        ].join("\n");
        return {
          content: [{ type: "text", text }],
          details: { backend: backend.name, query, count: results.length },
        };
      } catch (error) {
        return errorResult(
          `Search failed (${backend.name}): ${error instanceof Error ? error.message : String(error)}`,
        );
      }
    },
  });
}

// --- backends -------------------------------------------------------------

type Backend = {
  name: string;
  search(query: string, count: number): Promise<SearchResult[]>;
};

async function selectBackend(): Promise<Backend | undefined> {
  const config = loadConfig();
  const kagiKey = readSecretFile(config.kagiApiKeyFile);
  if (kagiKey) return kagiBackend(kagiKey);
  const kagiToken = readSecretFile(config.kagiSessionTokenFile);
  if (kagiToken) return kagiSessionBackend(kagiToken);
  const braveKey = readSecretFile(config.braveApiKeyFile);
  if (braveKey) return braveBackend(braveKey);
  return undefined;
}

function kagiBackend(key: string): Backend {
  return {
    name: "kagi",
    async search(query, count) {
      const url = `https://kagi.com/api/v0/search?q=${encodeURIComponent(query)}&limit=${count}`;
      const { status, body } = await curlGet(url, [
        "-H",
        `Authorization: Bot ${key}`,
      ]);
      if (status < 200 || status >= 300) {
        throw new Error(`HTTP ${status}: ${body.slice(0, 200)}`);
      }
      const parsed = JSON.parse(body) as {
        data?: Array<{
          t?: number;
          title?: string;
          url?: string;
          snippet?: string;
        }>;
      };
      return (parsed.data ?? [])
        .filter((item) => item.t === 0 && item.url)
        .slice(0, count)
        .map((item) => ({
          title: item.title ?? item.url ?? "",
          url: item.url ?? "",
          snippet: stripTags(item.snippet ?? ""),
        }));
    },
  };
}

// Session-token backend: drives Kagi's lightweight /html/search endpoint with a
// browser `kagi_session` cookie instead of the official (invite-only, metered)
// Search API. Same idea as the kagi-ken project. Keep it to human-scale volume —
// it rides your normal subscription session, so automated bursts are the thing
// most likely to draw attention.
function kagiSessionBackend(token: string): Backend {
  return {
    name: "kagi (session)",
    async search(query, count) {
      const url = `https://kagi.com/html/search?q=${encodeURIComponent(query)}`;
      const { status, body } = await curlGet(url, [
        "-H",
        `Cookie: kagi_session=${token}`,
      ]);
      if (status === 401 || status === 403) {
        throw new Error("invalid or expired session token");
      }
      if (status < 200 || status >= 300) {
        throw new Error(`HTTP ${status}: ${body.slice(0, 200)}`);
      }
      return parseKagiHtml(body, count);
    },
  };
}

function braveBackend(key: string): Backend {
  return {
    name: "brave",
    async search(query, count) {
      const url = `https://api.search.brave.com/res/v1/web/search?q=${encodeURIComponent(query)}&count=${count}`;
      const { status, body } = await curlGet(url, [
        "-H",
        "Accept: application/json",
        "-H",
        `X-Subscription-Token: ${key}`,
      ]);
      if (status < 200 || status >= 300) {
        throw new Error(`HTTP ${status}: ${body.slice(0, 200)}`);
      }
      const parsed = JSON.parse(body) as {
        web?: {
          results?: Array<{
            title?: string;
            url?: string;
            description?: string;
          }>;
        };
      };
      return (parsed.web?.results ?? []).slice(0, count).map((item) => ({
        title: stripTags(item.title ?? item.url ?? ""),
        url: item.url ?? "",
        snippet: stripTags(item.description ?? ""),
      }));
    },
  };
}

function loadConfig(): WebSearchConfig {
  const settings = mergeSettings(
    readJson(GLOBAL_SETTINGS),
    readJson(PROJECT_SETTINGS),
  ) as PiSettings;
  const config = settings.webSearch ?? {};
  for (const [key, value] of Object.entries(config)) {
    if (value !== undefined && typeof value !== "string") {
      throw new Error(`web_search: ${key} must be a string`);
    }
  }
  return config;
}

function readSecretFile(file: string | undefined): string | undefined {
  if (!file) return undefined;
  if (!path.isAbsolute(file)) {
    throw new Error("web_search: secret file paths must be absolute");
  }
  return fs.readFileSync(file, "utf8").trim() || undefined;
}

function readJson(file: string) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8")) as unknown;
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return {};
    throw err;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function mergeSettings(a: unknown, b: unknown): unknown {
  if (!isRecord(a) || !isRecord(b)) return b;
  return Object.fromEntries(
    [...new Set([...Object.keys(a), ...Object.keys(b)])].map((key) => [
      key,
      key in b ? mergeSettings(a[key], b[key]) : a[key],
    ]),
  );
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
  const re = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html))) {
    const attrs = m[1];
    if (!attrRe.test(attrs)) continue;
    const href = attrs.match(/href=["']([^"']*)["']/i)?.[1];
    if (!href || href.startsWith("#")) continue;
    const title = stripTags(m[2]);
    if (!title) continue;
    return { url: href, title };
  }
  return null;
}

// --- http -----------------------------------------------------------------

async function curlGet(url: string, extraArgs: string[] = []) {
  const args = [
    "-sS",
    "-L",
    "--compressed",
    "--max-time",
    "30",
    "-A",
    browserUserAgent,
    ...extraArgs,
    "-w",
    "\n%{http_code}\t%{content_type}",
    url,
  ];
  const { stdout } = await execFileAsync("curl", args, {
    encoding: "utf8",
    maxBuffer: 16 * 1024 * 1024,
  });
  const marker = stdout.lastIndexOf("\n");
  const body = marker === -1 ? stdout : stdout.slice(0, marker);
  const meta = marker === -1 ? "" : stdout.slice(marker + 1);
  const [statusText, contentType = ""] = meta.split("\t");
  return { status: Number(statusText) || 0, body, contentType };
}

// --- helpers --------------------------------------------------------------

function clampCount(value: number | undefined, fallback: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
  return Math.max(1, Math.min(20, Math.round(value)));
}

function errorResult(message: string) {
  return {
    content: [{ type: "text" as const, text: message }],
    isError: true,
    details: { error: message } as Record<string, unknown>,
  };
}

// Snippets from search backends may carry inline highlight tags (<b>, <em>).
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
