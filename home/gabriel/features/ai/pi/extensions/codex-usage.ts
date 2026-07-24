import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { mkdir, readFile, writeFile, appendFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { homedir } from "node:os";
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

type Usage = {
  input?: number;
  output?: number;
  cacheRead?: number;
  cacheWrite?: number;
  totalTokens?: number;
  cost?: {
    input?: number;
    output?: number;
    cacheRead?: number;
    cacheWrite?: number;
    total?: number;
  };
};

type UsageRecord = {
  id: string;
  timestamp: string;
  sessionFile?: string;
  provider: string;
  model: string;
  api?: string;
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
  totalTokens: number;
  cost: number;
  subscription: boolean;
  quota?: QuotaSnapshot;
};

type QuotaWindowSnapshot = {
  usedPercent?: number;
  limitWindowSeconds?: number;
  resetAfterSeconds?: number;
  resetAt?: number;
};

type QuotaSnapshot = {
  timestamp: string;
  plan?: string;
  allowed?: boolean;
  limitReached?: boolean;
  rateLimitReachedType?: string | null;
  primaryWindow?: QuotaWindowSnapshot;
  secondaryWindow?: QuotaWindowSnapshot;
};

type QuotaProbeResult = {
  timestamp: string;
  ok: boolean;
  endpoint?: string;
  status?: number;
  error?: string;
  snapshot?: QuotaSnapshot;
  parsed?: QuotaDisplay;
  attempts?: Array<{ endpoint: string; status?: number; error?: string }>;
};

type QuotaWindowDisplay = {
  percentUsed?: number;
  limitWindowSeconds?: number;
  resetsAt?: string;
  resetsAtEpoch?: number;
};

type QuotaDisplay = {
  primary?: QuotaWindowDisplay;
  secondary?: QuotaWindowDisplay;
  plan?: string;
};

type Summary = {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
  totalTokens: number;
  cost: number;
  requests: number;
};

const stateDir =
  process.env.PI_CODEX_USAGE_DIR ??
  join(homedir(), ".local", "state", "pi-usage");
const usagePath = join(stateDir, "codex.jsonl");
const seenPath = join(stateDir, "codex-seen.json");
const quotaPath = join(stateDir, "codex-quota.json");

const codexUsageEndpoint = "https://chatgpt.com/backend-api/codex/usage";
const quotaStatusKey = "codex-quota";
const execFileAsync = promisify(execFile);
const browserUserAgent =
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36";

export default function codexUsage(pi: ExtensionAPI) {
  let seen = new Set<string>();
  let quota: QuotaProbeResult | undefined;

  async function initialize() {
    await mkdir(stateDir, { recursive: true });
    seen = await readSeen();
    quota = await readJson<QuotaProbeResult>(quotaPath);
  }

  void initialize();

  pi.on("session_start", async (_event, ctx) => {
    await initialize();
    quota = await probeQuota(ctx).catch((error: unknown) => ({
      timestamp: new Date().toISOString(),
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    }));
    await writeJson(quotaPath, quota);
    updateQuotaStatus(ctx, quota);
  });

  pi.on("model_select", async (event, ctx) => {
    if (event.model.provider !== "openai-codex") {
      updateQuotaStatus(ctx, undefined);
      return;
    }

    await initialize();
    updateQuotaStatus(ctx, quota);
    quota = await probeQuota(ctx).catch((error: unknown) => ({
      timestamp: new Date().toISOString(),
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    }));
    await writeJson(quotaPath, quota);
    updateQuotaStatus(ctx, quota);
  });

  pi.on("message_end", async (event, ctx) => {
    const message = event.message as {
      role?: string;
      provider?: string;
      model?: string;
      api?: string;
      usage?: Usage;
      timestamp?: number;
      content?: unknown;
      stopReason?: string;
    };

    if (message.role !== "assistant" || !message.usage) return;
    if (message.stopReason === "aborted" || message.stopReason === "error")
      return;

    const provider = message.provider ?? "unknown";
    const model = message.model ?? "unknown";
    const subscription = Boolean(
      ctx.model &&
      ctx.model.provider === provider &&
      ctx.modelRegistry.isUsingOAuth(ctx.model),
    );

    if (provider !== "openai-codex") return;

    const usage = normalizeUsage(message.usage);
    const sessionFile = ctx.sessionManager.getSessionFile() ?? undefined;
    const id = fingerprint({
      sessionFile,
      provider,
      model,
      api: message.api,
      usage,
      timestamp: message.timestamp,
      content: message.content,
    });
    if (seen.has(id)) return;

    const quotaAfterMessage = await probeQuota(ctx).catch(() => undefined);
    if (quotaAfterMessage) {
      await writeJson(quotaPath, quotaAfterMessage);
      updateQuotaStatus(ctx, quotaAfterMessage);
    }

    const record: UsageRecord = {
      id,
      timestamp: new Date(message.timestamp ?? Date.now()).toISOString(),
      sessionFile,
      provider,
      model,
      api: message.api,
      input: usage.input,
      output: usage.output,
      cacheRead: usage.cacheRead,
      cacheWrite: usage.cacheWrite,
      totalTokens: usage.totalTokens,
      cost: usage.cost,
      subscription,
      quota: quotaAfterMessage?.snapshot,
    };

    seen.add(id);
    await appendJsonl(usagePath, record);
    await writeSeen(seen);
  });

  pi.registerCommand("codex-usage", {
    description: "Show tallied Codex/ChatGPT subscription token usage",
    handler: async (args, ctx) => {
      await initialize();
      const records = await readUsageRecords();
      const now = Date.now();
      const range = parseRange(args);
      const filtered = records.filter(
        (record) => record.provider === "openai-codex",
      );
      const ranged = filtered.filter(
        (record) => new Date(record.timestamp).getTime() >= now - range.ms,
      );
      const byModel = groupByModel(ranged);
      const total = summarize(ranged);
      quota = await readJson<QuotaProbeResult>(quotaPath);

      const lines = [
        `Codex/sub usage (${range.label}): ${formatSummary(total)}`,
        ...Object.entries(byModel)
          .sort((a, b) => b[1].cost - a[1].cost)
          .map(([model, summary]) => `  ${model}: ${formatSummary(summary)}`),
        quotaLine(quota),
        quotaEstimateLine(ranged, quota?.snapshot),
        `Log: ${usagePath}`,
      ];

      ctx.ui.notify(lines.join("\n"), "info");
    },
  });
}

function normalizeUsage(
  usage: Usage,
): Required<
  Pick<
    UsageRecord,
    "input" | "output" | "cacheRead" | "cacheWrite" | "totalTokens" | "cost"
  >
> {
  const input = usage.input ?? 0;
  const output = usage.output ?? 0;
  const cacheRead = usage.cacheRead ?? 0;
  const cacheWrite = usage.cacheWrite ?? 0;
  return {
    input,
    output,
    cacheRead,
    cacheWrite,
    totalTokens: usage.totalTokens ?? input + output + cacheRead + cacheWrite,
    cost: usage.cost?.total ?? 0,
  };
}

function fingerprint(value: unknown) {
  return createHash("sha256")
    .update(stableStringify(value))
    .digest("hex")
    .slice(0, 24);
}

function stableStringify(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  const object = value as Record<string, unknown>;
  return `{${Object.keys(object)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${stableStringify(object[key])}`)
    .join(",")}}`;
}

async function readSeen() {
  const values = await readJson<string[]>(seenPath);
  return new Set(Array.isArray(values) ? values : []);
}

async function writeSeen(seen: Set<string>) {
  await writeJson(seenPath, [...seen].slice(-10_000));
}

async function readUsageRecords() {
  if (!existsSync(usagePath)) return [];
  const text = await readFile(usagePath, "utf8");
  return text
    .split("\n")
    .filter(Boolean)
    .flatMap((line) => {
      try {
        return [JSON.parse(line) as UsageRecord];
      } catch {
        return [];
      }
    });
}

async function readJson<T>(path: string): Promise<T | undefined> {
  try {
    return JSON.parse(await readFile(path, "utf8")) as T;
  } catch {
    return undefined;
  }
}

async function writeJson(path: string, value: unknown) {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

async function appendJsonl(path: string, value: unknown) {
  await mkdir(dirname(path), { recursive: true });
  await appendFile(path, `${JSON.stringify(value)}\n`, "utf8");
}

function parseRange(args: string | undefined) {
  const arg = (args ?? "").trim().toLowerCase();
  if (arg === "day" || arg === "daily")
    return { label: "day", ms: 24 * 60 * 60 * 1000 };
  if (arg === "month" || arg === "monthly")
    return { label: "month", ms: 30 * 24 * 60 * 60 * 1000 };
  if (arg === "all") return { label: "all", ms: Number.POSITIVE_INFINITY };
  return { label: "week", ms: 7 * 24 * 60 * 60 * 1000 };
}

function summarize(records: UsageRecord[]): Summary {
  return records.reduce<Summary>(
    (acc, record) => ({
      input: acc.input + record.input,
      output: acc.output + record.output,
      cacheRead: acc.cacheRead + record.cacheRead,
      cacheWrite: acc.cacheWrite + record.cacheWrite,
      totalTokens: acc.totalTokens + record.totalTokens,
      cost: acc.cost + record.cost,
      requests: acc.requests + 1,
    }),
    {
      input: 0,
      output: 0,
      cacheRead: 0,
      cacheWrite: 0,
      totalTokens: 0,
      cost: 0,
      requests: 0,
    },
  );
}

function groupByModel(records: UsageRecord[]) {
  const groups: Record<string, UsageRecord[]> = {};
  for (const record of records) {
    const key = `${record.provider}/${record.model}`;
    groups[key] ??= [];
    groups[key].push(record);
  }
  return Object.fromEntries(
    Object.entries(groups).map(([key, values]) => [key, summarize(values)]),
  );
}

function formatSummary(summary: Summary) {
  return [
    `${summary.requests} req`,
    `↑${formatTokens(summary.input)}`,
    `↓${formatTokens(summary.output)}`,
    summary.cacheRead ? `R${formatTokens(summary.cacheRead)}` : undefined,
    summary.cacheWrite ? `W${formatTokens(summary.cacheWrite)}` : undefined,
    `$${summary.cost.toFixed(3)}`,
  ]
    .filter(Boolean)
    .join(" ");
}

function formatTokens(tokens: number) {
  const abs = Math.abs(tokens);
  if (abs >= 1_000_000) return `${(tokens / 1_000_000).toFixed(1)}M`;
  if (abs >= 1_000) return `${Math.round(tokens / 1_000)}k`;
  return String(tokens);
}

function quotaEstimateLine(
  records: UsageRecord[],
  snapshot: QuotaSnapshot | undefined,
) {
  const parts = ["Quota estimate:"];
  for (const [name, key] of quotaWindows(snapshot)) {
    const estimate = estimateWindowCapacity(records, key);
    if (!estimate) continue;
    const label = quotaWindowLabel(name, snapshot?.[key]?.limitWindowSeconds);
    parts.push(
      `${label}≈${formatTokens(estimate.capacityTokens)} tokens (${formatTokens(estimate.tokensPerPercent)}/%)`,
    );
  }
  if (parts.length === 1)
    parts.push("need quota snapshots with a percentage delta");
  return parts.join(" ");
}

function estimateWindowCapacity(
  records: UsageRecord[],
  window: "primaryWindow" | "secondaryWindow",
) {
  const withQuota = records
    .filter((record) => record.quota?.[window]?.usedPercent !== undefined)
    .sort((a, b) => a.timestamp.localeCompare(b.timestamp));
  if (withQuota.length < 2) return undefined;
  const first = withQuota[0];
  const last = withQuota[withQuota.length - 1];
  const firstPercent = first.quota?.[window]?.usedPercent;
  const lastPercent = last.quota?.[window]?.usedPercent;
  if (firstPercent === undefined || lastPercent === undefined) return undefined;
  const deltaPercent = lastPercent - firstPercent;
  if (deltaPercent <= 0) return undefined;
  const firstIndex = records.indexOf(first);
  const lastIndex = records.indexOf(last);
  const tokens = records
    .slice(Math.max(0, firstIndex + 1), lastIndex + 1)
    .reduce((sum, record) => sum + record.totalTokens, 0);
  if (tokens <= 0) return undefined;
  const tokensPerPercent = tokens / deltaPercent;
  return {
    tokensPerPercent,
    capacityTokens: tokensPerPercent * 100,
  };
}

async function probeQuota(ctx: {
  modelRegistry: {
    getApiKeyForProvider: (provider: string) => Promise<string | undefined>;
  };
}): Promise<QuotaProbeResult> {
  const token = await ctx.modelRegistry.getApiKeyForProvider("openai-codex");
  if (!token) {
    return {
      timestamp: new Date().toISOString(),
      ok: false,
      error: "No openai-codex OAuth token available",
    };
  }

  const accountId = extractAccountId(token);
  const endpoints = process.env.PI_CODEX_USAGE_URLS?.split(",")
    .map((part) => part.trim())
    .filter(Boolean) ?? [codexUsageEndpoint];
  const attempts: Array<{ endpoint: string; status?: number; error?: string }> =
    [];

  for (const endpoint of endpoints) {
    try {
      const response = await curlJson(endpoint, token, accountId);
      attempts.push({ endpoint, status: response.status });
      const body = response.body;
      if (response.status < 200 || response.status >= 300) continue;
      const timestamp = new Date().toISOString();
      const snapshot = quotaSnapshot(body, timestamp);
      return {
        timestamp,
        ok: true,
        endpoint,
        status: response.status,
        snapshot,
        parsed: quotaDisplay(snapshot),
        attempts,
      };
    } catch (error) {
      attempts.push({
        endpoint,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  return {
    timestamp: new Date().toISOString(),
    ok: false,
    error: "No known quota endpoint returned 2xx",
    attempts,
  };
}

async function curlJson(
  endpoint: string,
  token: string,
  accountId: string | undefined,
) {
  const headers = [
    `Authorization: Bearer ${token}`,
    ...(accountId ? [`chatgpt-account-id: ${accountId}`] : []),
    "originator: pi",
    "accept: application/json",
    `user-agent: ${browserUserAgent}`,
  ];
  const args = [
    "-sS",
    "-L",
    "--max-time",
    "15",
    ...headers.flatMap((header) => ["-H", header]),
    "-w",
    "\n%{http_code}",
    endpoint,
  ];
  const { stdout } = await execFileAsync("curl", args, {
    encoding: "utf8",
    maxBuffer: 2 * 1024 * 1024,
  });
  const marker = stdout.lastIndexOf("\n");
  const rawBody = marker === -1 ? stdout : stdout.slice(0, marker);
  const statusText = marker === -1 ? "0" : stdout.slice(marker + 1).trim();
  const status = Number(statusText) || 0;
  let body: unknown = rawBody;
  try {
    body = JSON.parse(rawBody);
  } catch {
    // Keep non-JSON bodies as strings so failed probes remain inspectable.
  }
  return { status, body };
}

function extractAccountId(token: string) {
  try {
    const [, payload] = token.split(".");
    if (!payload) return undefined;
    const json = JSON.parse(
      Buffer.from(payload, "base64url").toString("utf8"),
    ) as Record<string, unknown>;
    const auth = json["https://api.openai.com/auth"] as
      | Record<string, unknown>
      | undefined;
    return typeof auth?.chatgpt_account_id === "string"
      ? auth.chatgpt_account_id
      : undefined;
  } catch {
    return undefined;
  }
}

function quotaSnapshot(
  value: unknown,
  timestamp = new Date().toISOString(),
): QuotaSnapshot | undefined {
  if (!value || typeof value !== "object") return undefined;
  const object = value as Record<string, unknown>;
  const rateLimit = object.rate_limit as Record<string, unknown> | undefined;
  const plan =
    typeof object.plan_type === "string" ? object.plan_type : undefined;
  const rateLimitReachedType =
    typeof object.rate_limit_reached_type === "string"
      ? object.rate_limit_reached_type
      : object.rate_limit_reached_type === null
        ? null
        : undefined;
  return {
    timestamp,
    plan,
    allowed:
      typeof rateLimit?.allowed === "boolean" ? rateLimit.allowed : undefined,
    limitReached:
      typeof rateLimit?.limit_reached === "boolean"
        ? rateLimit.limit_reached
        : undefined,
    rateLimitReachedType,
    primaryWindow: quotaWindowSnapshot(rateLimit?.primary_window),
    secondaryWindow: quotaWindowSnapshot(rateLimit?.secondary_window),
  };
}

function quotaWindowSnapshot(value: unknown): QuotaWindowSnapshot | undefined {
  if (!value || typeof value !== "object") return undefined;
  const object = value as Record<string, unknown>;
  return {
    usedPercent: coercePercent(object.used_percent),
    limitWindowSeconds:
      typeof object.limit_window_seconds === "number"
        ? object.limit_window_seconds
        : undefined,
    resetAfterSeconds:
      typeof object.reset_after_seconds === "number"
        ? object.reset_after_seconds
        : undefined,
    resetAt: typeof object.reset_at === "number" ? object.reset_at : undefined,
  };
}

function quotaDisplay(snapshot: QuotaSnapshot | undefined): QuotaDisplay {
  return {
    primary: quotaWindowDisplay(snapshot?.primaryWindow),
    secondary: quotaWindowDisplay(snapshot?.secondaryWindow),
    plan: snapshot?.plan,
  };
}

function quotaWindowDisplay(
  window: QuotaWindowSnapshot | undefined,
): QuotaWindowDisplay | undefined {
  if (!window) return undefined;
  const resetsAtEpoch = window.resetAt;
  return {
    percentUsed: window.usedPercent,
    limitWindowSeconds: window.limitWindowSeconds,
    resetsAtEpoch,
    resetsAt: resetsAtEpoch
      ? new Date(resetsAtEpoch * 1000).toISOString()
      : undefined,
  };
}

function coercePercent(value: unknown) {
  if (typeof value !== "number") return undefined;
  if (!Number.isFinite(value)) return undefined;
  return value <= 1 ? value * 100 : value;
}

function quotaLine(result: QuotaProbeResult | undefined) {
  if (!result) return "Quota: no probe yet";
  if (!result.ok) return `Quota: probe failed (${result.error ?? "unknown"})`;
  const parsed = result.parsed ?? {};
  const windows = quotaWindowDisplays(parsed)
    .map(([name, window]) =>
      quotaWindowLine(
        quotaWindowLabel(name, window.limitWindowSeconds),
        window,
      ),
    )
    .filter((line): line is string => Boolean(line));
  const parts = ["Quota:", ...windows];
  if (windows.length === 0) parts.push("no window usage returned");
  if (parsed.plan) parts.push(`plan ${parsed.plan}`);
  parts.push(`via ${result.endpoint}`);
  return parts.join(" ");
}

function updateQuotaStatus(
  ctx: {
    model?: { provider?: string };
    ui: { setStatus(key: string, text: string | undefined): void };
  },
  result: QuotaProbeResult | undefined,
) {
  if (ctx.model?.provider !== "openai-codex") {
    ctx.ui.setStatus(quotaStatusKey, undefined);
    return;
  }

  ctx.ui.setStatus(quotaStatusKey, quotaStatusLine(result));
}

function quotaStatusLine(result: QuotaProbeResult | undefined) {
  if (!result?.ok) return undefined;
  const parsed = result.parsed ?? {};
  const parts = quotaWindowDisplays(parsed)
    .map(([name, window]) =>
      quotaWindowLeftLine(
        quotaWindowLabel(name, window.limitWindowSeconds),
        window,
      ),
    )
    .filter((line): line is string => Boolean(line));
  if (parts.length === 0) return undefined;
  return `[Quota left: ${parts.join("/")}]`;
}

function quotaWindows(
  snapshot: QuotaSnapshot | undefined,
): Array<["primary" | "secondary", "primaryWindow" | "secondaryWindow"]> {
  const windows: Array<
    ["primary" | "secondary", "primaryWindow" | "secondaryWindow"]
  > = [];
  if (snapshot?.primaryWindow) windows.push(["primary", "primaryWindow"]);
  if (snapshot?.secondaryWindow) windows.push(["secondary", "secondaryWindow"]);
  return windows;
}

function quotaWindowDisplays(
  display: QuotaDisplay,
): Array<["primary" | "secondary", QuotaWindowDisplay]> {
  const windows: Array<["primary" | "secondary", QuotaWindowDisplay]> = [];
  if (display.primary) windows.push(["primary", display.primary]);
  if (display.secondary) windows.push(["secondary", display.secondary]);
  return windows;
}

function quotaWindowLabel(
  fallback: "primary" | "secondary",
  seconds: number | undefined,
) {
  if (!seconds || !Number.isFinite(seconds) || seconds <= 0) return fallback;
  const units = [
    [7 * 24 * 60 * 60, "w"],
    [24 * 60 * 60, "d"],
    [60 * 60, "h"],
    [60, "m"],
  ] as const;
  for (const [unitSeconds, suffix] of units) {
    if (seconds % unitSeconds === 0) return `${seconds / unitSeconds}${suffix}`;
  }
  return `${seconds}s`;
}

function quotaWindowLeftLine(
  label: string,
  window: QuotaWindowDisplay | undefined,
) {
  if (!window?.percentUsed && window?.percentUsed !== 0) return undefined;
  const percentLeft = Math.max(0, Math.min(100, 100 - window.percentUsed));
  return `${percentLeft.toFixed(1)}% (${label})`;
}

function quotaWindowLine(
  label: string,
  window: QuotaWindowDisplay | undefined,
) {
  if (!window?.percentUsed && window?.percentUsed !== 0) return undefined;
  return [
    `${label} ${window.percentUsed.toFixed(1)}% used`,
    window.resetsAt ? `resets ${window.resetsAt}` : undefined,
  ]
    .filter(Boolean)
    .join(" ");
}
