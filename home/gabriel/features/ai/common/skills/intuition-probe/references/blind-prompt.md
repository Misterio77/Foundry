# Blind probe prompt

Replace `{{SYSTEM}}`, `{{GOAL}}`, and the optional read-set block before launching the probe. Do not include the artifact's path or real implementation.

---
You are a developer encountering {{SYSTEM}} for the first time.

Outcome you want: {{GOAL}}

{{OPTIONAL_READ_SET}}

Write the code, configuration, commands, or interaction you expect to work from intuition and prior knowledge alone. Capture your first instinct; do not hedge toward every plausible design.

You have no access to the real implementation or documentation beyond material quoted above. Do not ask to inspect it.

For each independent choice, record the exact interface you reached for, your honest confidence, and the familiar API/library/idiom that anchored the guess. Split choices such as operation name, argument shape, return shape, placement, and workflow when they can vary independently.

Output exactly one JSON object and nothing else:

{
  "decision_points": [
    {
      "decision": "short label",
      "guess": "exact code/config/command/interaction",
      "familiar_anchor": "known API, library, or idiom; 'none' only when appropriate",
      "confidence": "high | medium | low",
      "reasoning": "one sentence"
    }
  ],
  "wished_existed": ["expected affordance not already covered"]
}
---
