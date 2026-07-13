import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

import {
  createCodingTools,
  createReadOnlyTools,
  getAgentDir,
  type BashOperations,
  type EditOperations,
  type ExtensionAPI,
  type ExtensionCommandContext,
  type ExtensionContext,
  type ReadOperations,
  type ToolsOptions,
  type WriteOperations,
} from "@earendil-works/pi-coding-agent";
import {
  createHttpHooks,
  RealFSProvider,
  type SecretDefinition,
  VM,
} from "@earendil-works/gondolin";

const GUEST = "/workspace";
const STATUS = "gondolin";
const MODE_ENTRY = "gondolin-mode";
const AGENT_DIR = getAgentDir();
const GLOBAL_SETTINGS = path.join(AGENT_DIR, "settings.json");
const PROJECT_SETTINGS = path.join(process.cwd(), ".pi/settings.json");
const MODES = new Set(["", "toggle", "status", "on", "off"]);

type Tool = ReturnType<typeof createCodingTools>[number];
type ToolMap = Record<string, Tool>;
type GondolinModeEntry = {
  type?: string;
  customType?: string;
  data?: { enabled?: unknown };
};
type JsonSecret = Omit<SecretDefinition, "value"> & {
  env?: string;
  file?: string;
  cmd?: string | string[];
};
type HttpProxyConfig = {
  allowedHosts?: string[];
  replaceSecretsInQuery?: boolean;
  blockInternalRanges?: boolean;
  secrets?: Record<string, JsonSecret>;
};
type GondolinConfig = { httpProxy?: HttpProxyConfig; qemuPath?: string };
type PiSettings = { gondolin?: GondolinConfig };
type LazySecret = JsonSecret & { envName: string };
type SecretErrorNotifier = (message: string) => void;

function resolveSessionEnabled(entries: unknown, fallback = false) {
  if (!Array.isArray(entries)) return fallback;

  for (let i = entries.length - 1; i >= 0; i -= 1) {
    const entry = entries[i] as GondolinModeEntry;
    if (entry?.type !== "custom" || entry?.customType !== MODE_ENTRY) continue;
    if (typeof entry.data?.enabled === "boolean") return entry.data.enabled;
  }

  return fallback;
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

function loadConfig(): GondolinConfig {
  const settings = mergeSettings(
    readJson(GLOBAL_SETTINGS),
    readJson(PROJECT_SETTINGS),
  ) as PiSettings;
  const config = settings.gondolin ?? {};
  if (config.qemuPath !== undefined && typeof config.qemuPath !== "string") {
    throw new Error("gondolin: qemuPath must be a string");
  }
  return config;
}

function requireStringArray(
  value: unknown,
  name: string,
): string[] | undefined {
  if (value === undefined) return undefined;
  if (Array.isArray(value) && value.every((x) => typeof x === "string")) {
    return value;
  }
  throw new Error(`gondolin: ${name} must be an array of strings`);
}

function stripTrailingNewline(value: string) {
  return value.replace(/\r?\n$/, "");
}

function errorMessage(err: unknown) {
  return err instanceof Error ? err.message : String(err);
}

function readSecretFile(file: string) {
  if (!path.isAbsolute(file)) {
    throw new Error("gondolin: secret file paths must be absolute");
  }
  return stripTrailingNewline(fs.readFileSync(file, "utf8"));
}

function hasSecretSource(name: string, secret: JsonSecret) {
  return (
    process.env[secret.env ?? name] !== undefined ||
    secret.file !== undefined ||
    secret.cmd !== undefined
  );
}

function readSecretCmd(name: string, cmd: string | string[]) {
  const args = typeof cmd === "string" ? ["/bin/sh", "-lc", cmd] : cmd;
  if (!args.length || args.some((x) => typeof x !== "string")) {
    throw new Error("gondolin: secret cmd must be a string or string array");
  }

  try {
    return stripTrailingNewline(
      execFileSync(args[0], args.slice(1), {
        cwd: AGENT_DIR,
        encoding: "utf8",
        timeout: 30_000,
      }),
    );
  } catch (err) {
    throw new Error(
      `gondolin: secret command failed for httpProxy.secrets.${name}: ${errorMessage(
        err,
      )}`,
    );
  }
}

function readSecret(name: string, secret: LazySecret) {
  const value =
    process.env[secret.envName] ??
    (secret.file ? readSecretFile(secret.file) : undefined) ??
    (secret.cmd ? readSecretCmd(name, secret.cmd) : undefined);
  if (typeof value !== "string") {
    throw new Error(
      `gondolin: httpProxy.secrets.${name} needs env ${secret.envName}, file, or cmd`,
    );
  }
  return value;
}

function requestContainsSecretPlaceholder(
  request: Request,
  placeholder: string,
  replaceSecretsInQuery = false,
) {
  for (const value of request.headers.values()) {
    if (value.includes(placeholder)) return true;
  }

  if (!replaceSecretsInQuery) return false;
  try {
    for (const values of new URL(request.url).searchParams.values()) {
      if (values.includes(placeholder)) return true;
    }
  } catch {
    return request.url.includes(placeholder);
  }

  return false;
}

function createHttpProxy(
  config: GondolinConfig,
  onSecretError?: SecretErrorNotifier,
) {
  const httpProxy = config.httpProxy;
  if (!httpProxy) return { env: {} };

  const lazySecrets = new Map<string, LazySecret>();
  const secrets = Object.fromEntries(
    Object.entries(httpProxy.secrets ?? {}).map(([name, secret]) => {
      const envName = secret.env ?? name;
      if (!hasSecretSource(name, secret)) {
        throw new Error(
          `gondolin: httpProxy.secrets.${name} needs env ${envName}, file, or cmd`,
        );
      }

      lazySecrets.set(name, { ...secret, envName });
      return [
        name,
        {
          hosts:
            requireStringArray(
              secret.hosts,
              `httpProxy.secrets.${name}.hosts`,
            ) ?? [],
          value: `GONDOLIN_UNRESOLVED_SECRET_${name}`,
          placeholder: secret.placeholder,
        } satisfies SecretDefinition,
      ];
    }),
  );

  const allowedHosts = requireStringArray(
    httpProxy.allowedHosts,
    "httpProxy.allowedHosts",
  );
  const proxy = createHttpHooks({
    allowedHosts,
    allowedInternalHosts: allowedHosts,
    replaceSecretsInQuery: httpProxy.replaceSecretsInQuery,
    blockInternalRanges: httpProxy.blockInternalRanges,
    secrets,
  });

  const onRequest = proxy.httpHooks.onRequest;
  proxy.httpHooks.onRequest = async (request) => {
    const usedSecrets: string[] = [];
    try {
      for (const entry of proxy.secretManager.listSecrets()) {
        const secret = lazySecrets.get(entry.name);
        if (
          secret &&
          requestContainsSecretPlaceholder(
            request,
            entry.placeholder,
            httpProxy.replaceSecretsInQuery,
          )
        ) {
          try {
            proxy.secretManager.updateSecret(entry.name, {
              value: readSecret(entry.name, secret),
            });
          } catch (err) {
            onSecretError?.(
              `Gondolin failed to read secret ${entry.name}: ${errorMessage(
                err,
              )}`,
            );
            throw err;
          }
          usedSecrets.push(entry.name);
        }
      }

      return await onRequest?.(request);
    } finally {
      for (const name of usedSecrets) {
        proxy.secretManager.updateSecret(name, {
          value: `GONDOLIN_UNRESOLVED_SECRET_${name}`,
        });
      }
    }
  };

  return proxy;
}

const quote = (s: string) => `'${s.replace(/'/g, "'\\''")}'`;
const env = (e?: NodeJS.ProcessEnv) =>
  e &&
  Object.fromEntries(
    Object.entries(e).filter(
      (x): x is [string, string] => typeof x[1] === "string",
    ),
  );

function guestPath(cwd: string, p: string) {
  const rel = path.relative(cwd, path.isAbsolute(p) ? p : path.join(cwd, p));
  if (rel === "") return GUEST;
  if (rel.startsWith("..") || path.isAbsolute(rel))
    throw new Error(`path escapes workspace: ${p}`);
  return path.posix.join(GUEST, rel.split(path.sep).join(path.posix.sep));
}

async function checked(vm: VM, args: string[], label: string) {
  const r = await vm.exec(args);
  if (!r.ok) throw new Error(`${label} (${r.exitCode}): ${r.stderr}`);
  return r;
}

function readOps(vm: VM, cwd: string): ReadOperations {
  return {
    readFile: async (p) =>
      (await checked(vm, ["/bin/cat", guestPath(cwd, p)], "cat failed"))
        .stdoutBuffer,
    access: async (p) => {
      if (
        !(
          await vm.exec([
            "/bin/sh",
            "-lc",
            `test -r ${quote(guestPath(cwd, p))}`,
          ])
        ).ok
      ) {
        throw new Error(`not readable: ${p}`);
      }
    },
    detectImageMimeType: async (p) => {
      const r = await vm.exec([
        "/bin/sh",
        "-lc",
        `file --mime-type -b ${quote(guestPath(cwd, p))}`,
      ]);
      const mime = r.ok ? r.stdout.trim() : "";
      return ["image/jpeg", "image/png", "image/gif", "image/webp"].includes(
        mime,
      )
        ? mime
        : null;
    },
  };
}

function writeOps(vm: VM, cwd: string): WriteOperations {
  return {
    writeFile: async (p, content) => {
      const dest = guestPath(cwd, p);
      await checked(
        vm,
        [
          "/bin/sh",
          "-lc",
          [
            "set -eu",
            `mkdir -p ${quote(path.posix.dirname(dest))}`,
            `printf %s ${quote(Buffer.from(content).toString("base64"))} | base64 -d > ${quote(dest)}`,
          ].join("\n"),
        ],
        "write failed",
      );
    },
    mkdir: async (p) =>
      void (await checked(
        vm,
        ["/bin/mkdir", "-p", guestPath(cwd, p)],
        "mkdir failed",
      )),
  };
}

function editOps(vm: VM, cwd: string): EditOperations {
  const read = readOps(vm, cwd);
  const write = writeOps(vm, cwd);
  return {
    readFile: read.readFile,
    access: read.access,
    writeFile: write.writeFile,
  };
}

function bashOps(
  vm: VM,
  cwd: string,
  defaultEnv: Record<string, string> = {},
): BashOperations {
  return {
    exec: async (command, dir, { onData, signal, timeout, env: e }) => {
      const ac = new AbortController();
      const abort = () => ac.abort();
      signal?.addEventListener("abort", abort, { once: true });
      let timedOut = false;
      const timer = timeout
        ? setTimeout(() => {
            timedOut = true;
            ac.abort();
          }, timeout * 1000)
        : undefined;

      try {
        const proc = vm.exec(["/bin/bash", "-lc", command], {
          cwd: guestPath(cwd, dir),
          env: { ...env(e), ...defaultEnv },
          signal: ac.signal,
          stderr: "pipe",
          stdout: "pipe",
        });
        for await (const chunk of proc.output()) onData(chunk.data);
        return { exitCode: (await proc).exitCode };
      } catch (err) {
        if (signal?.aborted) throw new Error("aborted");
        if (timedOut) throw new Error(`timeout:${timeout}`);
        throw err;
      } finally {
        if (timer) clearTimeout(timer);
        signal?.removeEventListener("abort", abort);
      }
    },
  };
}

export default function (pi: ExtensionAPI) {
  const cwd = process.cwd();
  const config = loadConfig();
  let notifySecretError: SecretErrorNotifier = () => {};
  const pendingSecretErrors: string[] = [];
  const httpProxy = createHttpProxy(config, (message) => {
    pendingSecretErrors.push(message);
    notifySecretError(message);
  });
  let enabled = false;
  let vm: VM | null = null;
  let starting: Promise<VM> | null = null;

  const status = (
    ctx: ExtensionContext,
    text: string,
    color: "accent" | "muted" = "accent",
  ) => ctx.ui.setStatus(STATUS, ctx.ui.theme.fg(color, `Gondolin: ${text}`));

  async function start(ctx?: ExtensionContext) {
    if (ctx) notifySecretError = (message) => ctx.ui.notify(message, "error");
    if (!enabled) throw new Error("Gondolin is disabled");
    if (vm) return vm;
    if (starting) return starting;

    ctx && status(ctx, `starting (mount ${GUEST})`);
    starting = VM.create({
      httpHooks: "httpHooks" in httpProxy ? httpProxy.httpHooks : undefined,
      env: httpProxy.env,
      vfs: { mounts: { [GUEST]: new RealFSProvider(cwd) } },
      sandbox: config.qemuPath ? { qemuPath: config.qemuPath } : undefined,
    }).then(async (next) => {
      if (!enabled) {
        await next.close();
        throw new Error("Gondolin was disabled while starting");
      }
      vm = next;
      ctx && status(ctx, `running (${cwd} -> ${GUEST})`);
      ctx?.ui.notify(
        `Gondolin VM ready. Host ${cwd} mounted at ${GUEST}`,
        "info",
      );
      return next;
    });

    try {
      return await starting;
    } finally {
      starting = null;
    }
  }

  async function stop(ctx?: ExtensionContext) {
    const old = vm ?? (starting && (await starting.catch(() => null)));
    vm = starting = null;
    if (old) {
      ctx && status(ctx, "stopping", "muted");
      await old.close();
    }
  }

  const setEnabled = (value: boolean) => {
    enabled = value;
    pi.appendEntry(MODE_ENTRY, { enabled });
  };

  async function setMode(mode: string, ctx: ExtensionContext, wait = false) {
    if (wait && "waitForIdle" in ctx) {
      await (ctx as ExtensionCommandContext).waitForIdle();
    } else if (!ctx.isIdle()) {
      return ctx.ui.notify("Gondolin can only toggle while idle", "error");
    }
    setEnabled(mode === "" || mode === "toggle" ? !enabled : mode === "on");
    if (enabled) {
      await start(ctx);
      return ctx.ui.notify("Gondolin enabled; tools now run in the VM", "info");
    }

    await stop(ctx);
    status(ctx, "disabled", "muted");
    ctx.ui.notify("Gondolin disabled; tools now run on the host", "info");
  }

  const toolMap = (tools: Tool[]) =>
    Object.fromEntries(tools.map((tool) => [tool.name, tool])) as ToolMap;
  const codingTools = (options?: ToolsOptions) =>
    toolMap(createCodingTools(cwd, options));
  const localTools = toolMap([
    ...createCodingTools(cwd),
    ...createReadOnlyTools(cwd).filter((tool) => tool.name !== "read"),
  ]);
  const sandboxedTools = (vm: VM) =>
    codingTools({
      read: { operations: readOps(vm, cwd) },
      write: { operations: writeOps(vm, cwd) },
      edit: { operations: editOps(vm, cwd) },
      bash: { operations: bashOps(vm, cwd, httpProxy.env) },
    });

  function registerSandboxedTool(name: "read" | "write" | "edit" | "bash") {
    const local = localTools[name];
    pi.registerTool({
      ...local,
      async execute(id, params, signal, onUpdate, ctx) {
        const tool = enabled ? sandboxedTools(await start(ctx))[name] : local;
        return tool.execute(id, params, signal, onUpdate);
      },
    });
  }

  function registerHostOnlyTool(name: "find" | "grep" | "ls") {
    const local = localTools[name];
    pi.registerTool({
      ...local,
      async execute(id, params, signal, onUpdate, ctx) {
        if (enabled) {
          throw new Error(
            `${name} is disabled while Gondolin is enabled. Use bash to run it instead.`,
          );
        }
        return local.execute(id, params, signal, onUpdate);
      },
    });
  }

  pi.on("session_start", async (_event, ctx) => {
    enabled = resolveSessionEnabled(
      ctx.sessionManager.getBranch?.() ?? ctx.sessionManager.getEntries(),
    );
    if (!enabled) return status(ctx, "disabled", "muted");
    try {
      await start(ctx);
    } catch (err) {
      if (enabled) throw err;
    }
  });

  pi.on("session_shutdown", async () => {
    await stop();
  });

  pi.on("tool_result", (event) => {
    if (!pendingSecretErrors.length) return;
    const errors = pendingSecretErrors.splice(0);
    return {
      content: [
        ...event.content,
        {
          type: "text" as const,
          text: `\nGondolin proxy errors:\n${errors.map((x) => `- ${x}`).join("\n")}`,
        },
      ],
      isError: true,
    };
  });

  pi.registerShortcut("ctrl+g", {
    description: "Toggle Gondolin VM sandboxing",
    handler: (ctx) => setMode("toggle", ctx),
  });

  pi.registerCommand("gondolin", {
    description: "Toggle Gondolin VM sandboxing (on/off/status)",
    handler: async (args, ctx) => {
      const mode = args.trim().toLowerCase();
      if (!MODES.has(mode))
        return ctx.ui.notify(
          "Usage: /gondolin [on|off|toggle|status]",
          "error",
        );
      if (mode === "status") {
        return ctx.ui.notify(
          enabled
            ? `Gondolin enabled${vm ? " and running" : " but not running"}; HTTP proxy: ${"httpHooks" in httpProxy ? "configured" : "off"}`
            : "Gondolin disabled",
          "info",
        );
      }

      await setMode(mode, ctx, true);
    },
  });

  for (const name of ["read", "write", "edit", "bash"] as const) {
    registerSandboxedTool(name);
  }

  for (const name of ["find", "grep", "ls"] as const) {
    registerHostOnlyTool(name);
  }

  const onUserBash = pi.on as unknown as (
    event: "user_bash",
    handler: (
      event: unknown,
      ctx: ExtensionContext,
    ) => Promise<{ operations: BashOperations } | undefined>,
  ) => void;

  onUserBash("user_bash", async (_event, ctx) => {
    if (!enabled) return;
    return { operations: bashOps(await start(ctx), cwd, httpProxy.env) };
  });

  pi.on("before_agent_start", async (event, ctx) => {
    if (!enabled) return;
    try {
      await start(ctx);
    } catch (err) {
      if (enabled) throw err;
      return;
    }
    return {
      systemPrompt: event.systemPrompt.replace(
        `Current working directory: ${cwd}`,
        `Current working directory: ${GUEST} (Gondolin VM, mounted from host: ${cwd})`,
      ),
    };
  });
}
