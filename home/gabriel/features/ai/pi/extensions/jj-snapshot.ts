import { statSync } from "node:fs";
import { dirname, join } from "node:path";

import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

const snapshotTimeoutMs = 30_000;

function findJjRepository(cwd: string): string | undefined {
  let directory = cwd;

  while (true) {
    try {
      if (statSync(join(directory, ".jj")).isDirectory()) {
        return directory;
      }
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") {
        throw error;
      }
    }

    const parent = dirname(directory);
    if (parent === directory) return undefined;
    directory = parent;
  }
}

export default function jjSnapshot(pi: ExtensionAPI) {
  let repository: string | undefined;
  let snapshotQueue = Promise.resolve();

  const snapshot = (ctx: ExtensionContext): Promise<void> => {
    const currentRepository = repository;
    if (!currentRepository) return Promise.resolve();

    const queued = snapshotQueue.then(async () => {
      const result = await pi.exec(
        "jj",
        ["--repository", currentRepository, "util", "snapshot", "--quiet"],
        { timeout: snapshotTimeoutMs },
      );

      if (result.code === 0) return;

      const detail = (result.stderr || result.stdout).trim();
      const message = `jj snapshot failed${detail ? `: ${detail}` : ""}`;
      if (ctx.hasUI) ctx.ui.notify(message, "warning");
      else console.error(message);
    });

    snapshotQueue = queued.catch((error: unknown) => {
      const detail = error instanceof Error ? error.message : String(error);
      const message = `jj snapshot failed: ${detail}`;
      if (ctx.hasUI) ctx.ui.notify(message, "warning");
      else console.error(message);
    });

    return snapshotQueue;
  };

  pi.on("session_start", async (_event, ctx) => {
    repository = findJjRepository(ctx.cwd);
    await snapshot(ctx);
  });

  pi.on("before_agent_start", async (_event, ctx) => {
    await snapshot(ctx);
  });

  pi.on("tool_execution_end", async (_event, ctx) => {
    await snapshot(ctx);
  });

  pi.on("agent_end", async (_event, ctx) => {
    await snapshot(ctx);
  });

  pi.on("session_shutdown", async (_event, ctx) => {
    await snapshot(ctx);
  });
}
