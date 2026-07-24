import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function modelContext(pi: ExtensionAPI) {
  pi.on("before_agent_start", async (event, ctx) => {
    const model = ctx.model
      ? `''${ctx.model.provider}/''${ctx.model.id}`
      : "unknown";

    return {
      systemPrompt: `
        ${event.systemPrompt}

        # LLM Model

        **Model**: ${model}
      `,
    };
  });
}
