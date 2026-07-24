/**
 * Expands inline bash commands in user prompts.
 *
 * Examples:
 *   What's in !{pwd}?
 *   Current change: !{jj log -r @ --no-graph -T 'change_id.short()'}
 *
 * Whole-line !command prompts are left alone so Pi's built-in user bash
 * behavior still handles them.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function inlineBash(pi: ExtensionAPI) {
  const pattern = /!\{([^}]+)\}/g;
  const timeoutMs = 30_000;

  pi.on("input", async (event, ctx) => {
    const text = event.text;
    const trimmedStart = text.trimStart();

    if (trimmedStart.startsWith("!") && !trimmedStart.startsWith("!{")) {
      return { action: "continue" };
    }

    if (!pattern.test(text)) {
      return { action: "continue" };
    }

    pattern.lastIndex = 0;

    let result = text;
    const expansions: Array<{
      command: string;
      output: string;
      error?: string;
    }> = [];
    const matches = [...text.matchAll(pattern)].map((match) => ({
      full: match[0],
      command: match[1],
    }));

    for (const { full, command } of matches) {
      try {
        const bashResult = await pi.exec("bash", ["-c", command], {
          timeout: timeoutMs,
        });
        const output = bashResult.stdout || bashResult.stderr || "";
        const trimmed = output.trim();

        expansions.push(
          bashResult.code !== 0 && bashResult.stderr
            ? {
                command,
                output: trimmed,
                error: `exit code ${bashResult.code}`,
              }
            : { command, output: trimmed },
        );
        result = result.replace(full, trimmed);
      } catch (err) {
        const error = err instanceof Error ? err.message : String(err);
        expansions.push({ command, output: "", error });
        result = result.replace(full, `[error: ${error}]`);
      }
    }

    if (ctx.hasUI && expansions.length > 0) {
      const summary = expansions
        .map((expansion) => {
          const status = expansion.error ? ` (${expansion.error})` : "";
          const preview =
            expansion.output.length > 50
              ? `${expansion.output.slice(0, 50)}...`
              : expansion.output;
          return `!{${expansion.command}}${status} -> "${preview}"`;
        })
        .join("\n");

      ctx.ui.notify(
        `Expanded ${expansions.length} inline command(s):\n${summary}`,
        "info",
      );
    }

    return { action: "transform", text: result, images: event.images };
  });
}
