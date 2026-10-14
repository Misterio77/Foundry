/**
 * Title prefix extension
 *
 * Pi overwrites the terminal title ("π - <cwd>") on startup, session switch
 * and rename, dropping the "[host] " prefix fish's default `fish_title` adds
 * when running over SSH. Hyprland window rules key host colors off that
 * prefix, so this re-adds it to every title Pi emits.
 *
 * Pi gives extensions no hook on the core's own title updates, so this wraps
 * `process.stdout.write` and rewrites OSC 0/2 title sequences in flight. The
 * prefix mirrors fish exactly: only when SSH_TTY is set, hostname truncated
 * to 10 characters.
 */

import { hostname } from "node:os";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// OSC 0 (icon+title) or OSC 2 (title), terminated by BEL or ST.
const titleSequence = /\x1b\](0|2);([^\x07\x1b]*)(\x07|\x1b\\)/g;

function titlePrefix(): string | undefined {
  if (!process.env.SSH_TTY) return undefined;
  const host = hostname().split(".")[0].slice(0, 10);
  return `[${host}] `;
}

export default function titlePrefixExtension(_pi: ExtensionAPI) {
  const prefix = titlePrefix();
  if (!prefix) return;

  const stdout = process.stdout as NodeJS.WriteStream & {
    __piTitlePrefixed?: boolean;
  };
  // Survive /reload without stacking wrappers.
  if (stdout.__piTitlePrefixed) return;
  stdout.__piTitlePrefixed = true;

  const originalWrite = stdout.write.bind(stdout);
  stdout.write = ((chunk: unknown, ...rest: unknown[]) => {
    if (typeof chunk === "string" && chunk.includes("\x1b]")) {
      chunk = chunk.replace(titleSequence, (_match, code, title, end) =>
        title.startsWith(prefix)
          ? `\x1b]${code};${title}${end}`
          : `\x1b]${code};${prefix}${title}${end}`,
      );
    }
    return (originalWrite as (...args: unknown[]) => boolean)(chunk, ...rest);
  }) as typeof stdout.write;
}
