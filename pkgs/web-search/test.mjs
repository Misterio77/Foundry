import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { parseKagiHtml, searchKagi } from "./search.mjs";

const html = `
<div class="search-result">
  <a class="__sri_title_link" href="https://example.org/?a=1&amp;b=2">Nix &amp; <b>friends</b></a>
  <div class="__sri-desc">A <em>highlight</em> &#x1f408; &quot;cat&quot;.</div>
</div>
<div class="__srgi">
  <div class="__srgi-title"><a href="https://example.org/group">Grouped result</a></div>
  <span class="__sri-desc">More&nbsp; text</span>
</div>
<div class="search-result"><a class="__sri_title_link" href="#skip">Skip</a></div>`;

test("parses regular/grouped results, highlights, and entities", () => {
  assert.deepEqual(parseKagiHtml(html, 8), [
    {
      title: "Nix & friends",
      url: "https://example.org/?a=1&b=2",
      snippet: 'A highlight 🐈 "cat".',
    },
    {
      title: "Grouped result",
      url: "https://example.org/group",
      snippet: "More text",
    },
  ]);
  assert.equal(parseKagiHtml(html, 1).length, 1);
  assert.deepEqual(parseKagiHtml("<p>No results</p>", 8), []);
});

test("uses the subscription endpoint with a timeout and no redirects", async () => {
  const results = await searchKagi(
    "test-token",
    "nix & cats",
    1,
    async (url, options) => {
      assert.equal(url.origin + url.pathname, "https://kagi.com/html/search");
      assert.equal(url.searchParams.get("q"), "nix & cats");
      assert.equal(options.headers.Cookie, "kagi_session=test-token");
      assert.equal(options.redirect, "manual");
      assert.ok(options.signal instanceof AbortSignal);
      return new Response(html);
    },
  );
  assert.equal(results.length, 1);
});

test("reports auth/HTTP errors instead of empty results", async () => {
  for (const status of [302, 401, 403, 429, 500]) {
    await assert.rejects(
      searchKagi(
        "test-token",
        "query",
        8,
        async () => new Response(null, { status }),
      ),
      status < 429 ? /renew/ : new RegExp(`HTTP ${status}`),
    );
  }
});

function cli(...args) {
  return spawnSync(
    process.execPath,
    [new URL("./cli.mjs", import.meta.url).pathname, ...args],
    {
      encoding: "utf8",
      env: {
        ...process.env,
        KAGI_SESSION_TOKEN_FILE: "/nonexistent/web-search-test-token",
      },
    },
  );
}

test("help needs no credentials", () => {
  const result = cli("--help");
  assert.equal(result.status, 0);
  assert.match(result.stdout, /Usage: web-search/);
  assert.equal(result.stderr, "");
});

test("invalid arguments fail before credentials/network access", () => {
  for (const args of [
    [],
    [" "],
    ["--count", "0", "query"],
    ["-n", "21", "query"],
    ["-n", "1.5", "query"],
    ["--unknown"],
  ]) {
    const result = cli(...args);
    assert.equal(result.status, 1);
    assert.equal(result.stdout, "");
    assert.doesNotMatch(result.stderr, /cannot read/);
  }
});

test("missing credentials give an actionable error on stderr", () => {
  const result = cli("query");
  assert.equal(result.status, 1);
  assert.equal(result.stdout, "");
  assert.match(result.stderr, /cannot read.*KAGI_SESSION_TOKEN_FILE/);
});

test("CLI prints text/JSON and handles empty results and tokens", () => {
  const dir = mkdtempSync(join(tmpdir(), "web-search-test-"));
  const file = join(dir, "token");
  const run = (body, ...args) =>
    spawnSync(
      process.execPath,
      [
        "--import",
        `data:text/javascript,${encodeURIComponent(`globalThis.fetch = async () => new Response(${JSON.stringify(body)});`)}`,
        new URL("./cli.mjs", import.meta.url).pathname,
        ...args,
      ],
      {
        encoding: "utf8",
        env: { ...process.env, KAGI_SESSION_TOKEN_FILE: file },
      },
    );
  try {
    writeFileSync(file, "fake-test-token\n");
    const json = run(html, "--json", "--count", "1", "nix", "cats");
    assert.equal(json.status, 0);
    assert.equal(json.stderr, "");
    assert.deepEqual(JSON.parse(json.stdout), parseKagiHtml(html, 1));
    const text = run(html, "nix", "cats");
    assert.equal(text.status, 0);
    assert.match(text.stdout, /Search results for "nix cats"/);
    assert.match(text.stdout, /1\. Nix & friends/);
    assert.doesNotMatch(text.stdout + text.stderr, /fake-test-token/);
    assert.deepEqual(JSON.parse(run("", "--json", "query").stdout), []);
    assert.match(run("", "query").stdout, /No results/);
    writeFileSync(file, "\n");
    const empty = run(html, "query");
    assert.equal(empty.status, 1);
    assert.equal(empty.stdout, "");
    assert.match(empty.stderr, /empty Kagi session-token/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
