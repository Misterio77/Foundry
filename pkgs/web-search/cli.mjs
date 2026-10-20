import fs from "node:fs";
import { parseArgs } from "node:util";
import { searchKagi } from "./search.mjs";

const help = `Usage: web-search [--count N] [--json] "query"

Search the web with your Kagi subscription. Returns titles, URLs, and snippets.

  -n, --count N  Maximum results, 1–20 (default: 8)
      --json     Print an array of {title, url, snippet} objects
  -h, --help     Show this help

KAGI_SESSION_TOKEN_FILE overrides /run/secrets/kagi_session_token.
Read full result pages with curl/trafilatura (see the web-fetch skill).
`;

try {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: {
      count: { type: "string", short: "n", default: "8" },
      json: { type: "boolean", default: false },
      help: { type: "boolean", short: "h", default: false },
    },
  });
  if (values.help) {
    console.log(help);
  } else {
    const query = positionals.join(" ").trim();
    if (!query)
      throw new Error("provide a search query; see web-search --help");
    if (
      !/^\d+$/.test(values.count) ||
      Number(values.count) < 1 ||
      Number(values.count) > 20
    ) {
      throw new Error("--count must be an integer from 1 to 20");
    }
    const file =
      process.env.KAGI_SESSION_TOKEN_FILE || "/run/secrets/kagi_session_token";
    let token;
    try {
      token = fs.readFileSync(file, "utf8").trim();
    } catch {
      throw new Error(
        `cannot read Kagi session-token file: ${file}; set KAGI_SESSION_TOKEN_FILE`,
      );
    }
    if (!token) throw new Error(`empty Kagi session-token file: ${file}`);
    const results = await searchKagi(token, query, Number(values.count));
    console.log(
      values.json
        ? JSON.stringify(results, null, 2)
        : results.length
          ? [
              `Search results for "${query}" (via Kagi):`,
              "",
              ...results.map(
                (r, i) =>
                  `${i + 1}. ${r.title}\n   ${r.url}${r.snippet ? `\n   ${r.snippet}` : ""}`,
              ),
            ].join("\n")
          : `No results for "${query}".`,
    );
  }
} catch (error) {
  console.error(`web-search: ${error.message}`);
  process.exitCode = 1;
}
