---
name: intuition-probe
description: Blind-test the intuitiveness of an API, CLI, config format, or UI by asking fresh isolated Pi processes what interface they expect before inspecting the real artifact. Use for API/DX/UX intuition probes, expected affordances, and "make the API whatever the LLM guesses".
---

# Intuition probe

Use a model's prior as a cheap sample of familiar interface conventions. A divergent guess is a design candidate, not merely a model error. Prefer conforming the interface to a convergent familiar guess unless safety or a hard invariant forbids it.

This is adapted for Pi from Jeremy Theocharis's [intuition-probe](https://gist.github.com/JeremyTheocharis/83c76da5a10bcf495d4298c70fee91b4), itself based on Anselm Eickhoff's Jazz principle: “make the API whatever the LLM guesses.”

## Guardrails

- Ordering is the experiment: freeze the blind prompt, then inspect reality, then launch probes.
- Never expose artifact paths, implementation details, exact identifiers, or the answer key to a probe.
- One sample produces candidates only. Call something a priority only when at least two independent samples converge.
- The probes are isolated `pi -p` processes with tools, extensions, skills, context files, prompt templates, and sessions disabled. Do not use a subagent tool.
- Never edit the artifact under test as part of this skill; report recommendations only.

## Procedure

1. Ask for the artifact, rough outcome, optional read-set, and sample count (default 1). Do not inspect the artifact yet.
2. Rewrite the outcome without leaked method names, keys, flags, labels, paths, or implementation clues. Ask the user to confirm the sanitized goal.
3. Read [references/blind-prompt.md](references/blind-prompt.md). Fill its placeholders in a temporary prompt file. A read-set is allowed verbatim; fetch URL content and inline it rather than giving the probe a URL. Freeze this file now.
4. Only now inspect the real API signatures, schema/examples, CLI help/definitions, or UI routes/components. This is the answer key and stays in the orchestrator context.
5. Run the probes from this skill directory:

   ```bash
   bash scripts/run-blind.sh /path/to/frozen-prompt.md N
   ```

   The script prints an output directory containing `probe-*.json` and logs. Read every result. If a probe emits invalid JSON, preserve it as a failed sample; do not quietly repair its design choices.
6. Compare every decision against reality using [references/scoring.md](references/scoring.md). Fold duplicate/hedged decisions explicitly rather than dropping them.
7. Group equivalent guesses across samples. Convergence means the same semantic shape, not merely similar wording.
8. Report:
   - mode (`cold` or `doc-informed`), model, and N;
   - the candidate interface/spec the probes reached for;
   - divergences with bucket, confidence/convergence, familiar anchor, and conform-first recommendation;
   - matches briefly;
   - rejected conform moves and the concrete safety/invariant reason;
   - limitations: same-model samples are repeated draws, not independent human usability evidence.

For N=1, label the report **candidate only — not a confirmed familiar default**. Offer to save it outside the repository under test.
