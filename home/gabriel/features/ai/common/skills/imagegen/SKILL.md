---
name: imagegen
description: Generate or edit raster images with the codex-imagegen CLI using Codex ChatGPT authentication. Use when the user explicitly requests generated images, image edits, or visual variants; prefer editing existing SVG/vector/code-native assets when appropriate.
---

# Image generation

Use `codex-imagegen` for image generation and editing, only on a clear user request:

```bash
codex-imagegen generate --prompt "description" --out output.png
codex-imagegen edit --image input.png --prompt "changes" --out output.png
codex-imagegen batch --input jobs.jsonl --out-dir out/   # one JSON job per line
```

Useful flags:

- `--n N` for several candidates at once; `--prompt-file` for long prompts.
- `--size WIDTHxHEIGHT` (or `auto`), `--quality`, `--background` to steer output;
  `--size-policy error` when the exact dimensions matter.
- `edit` takes `--image` one to five times, plus `--style-image`.
- `--dry-run` validates arguments without spending quota. `--help` has the rest.

Authentication uses `$CODEX_HOME/auth.json` or `~/.codex/auth.json` from
`codex login`, not the agent provider's credentials. Do not read auth files into
context. Do not automatically rerun failed requests: quota may already have been
consumed. Inspect saved images and show them inline using Markdown.
