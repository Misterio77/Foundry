---
name: imagegen
description: Generate or edit raster images with the codex-imagegen CLI using Codex ChatGPT authentication. Use when the user explicitly requests generated images, image edits, or visual variants; prefer editing existing SVG/vector/code-native assets when appropriate.
---

# Image generation

Use `codex-imagegen` for image generation and editing, only on a clear user request:

```bash
codex-imagegen generate --prompt "description" --out output.png
codex-imagegen edit --image input.png --prompt "changes" --out output.png
```

Use `--help` for options and `--dry-run` to validate without spending quota.
Authentication uses `$CODEX_HOME/auth.json` or `~/.codex/auth.json` from `codex login`,
not Pi credentials. Do not read auth files into context. Do not automatically
rerun failed requests: quota may already have been consumed. Inspect saved images
and show them inline using Markdown.
