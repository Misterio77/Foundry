import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import {
  createEditToolDefinition,
  type EditToolInput,
  type ExtensionAPI,
  type ExtensionCommandContext,
} from "@earendil-works/pi-coding-agent";

const STATE_DIR = path.join(
  process.env.XDG_STATE_HOME ?? path.join(os.homedir(), ".local/state"),
  "llm-suggest",
);
const SUGGESTIONS_FILE =
  process.env.LLM_SUGGEST_FILE ?? path.join(STATE_DIR, "suggestions.json");

const editDefinition = createEditToolDefinition(process.cwd());

type SuggestionEdit = {
  replacement: string;
  range: {
    start: { line: number; character: number };
    end: { line: number; character: number };
  };
};

type Suggestion = {
  id: string;
  file: string;
  title?: string;
  message: string;
  severity: number;
  range: SuggestionEdit["range"];
  edits: SuggestionEdit[];
  createdAt: string;
};

type ClearParams = {
  file?: string;
};

type MatchedEdit = {
  editIndex: number;
  start: number;
  end: number;
  newText: string;
};

function readSuggestions(): Suggestion[] {
  try {
    const data = JSON.parse(
      fs.readFileSync(SUGGESTIONS_FILE, "utf8"),
    ) as unknown;
    return Array.isArray(data) ? (data as Suggestion[]) : [];
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw err;
  }
}

function writeSuggestions(suggestions: Suggestion[]) {
  fs.mkdirSync(STATE_DIR, { recursive: true });
  fs.writeFileSync(
    SUGGESTIONS_FILE,
    `${JSON.stringify(suggestions, null, 2)}\n`,
  );
}

function resolveFile(cwd: string, file: string) {
  return path.resolve(cwd, file.startsWith("@") ? file.slice(1) : file);
}

function normalizeToLf(value: string) {
  return value.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
}

function lspPosition(content: string, offset: number) {
  const before = content.slice(0, offset);
  const lastNewline = before.lastIndexOf("\n");
  return {
    line: before.split("\n").length - 1,
    character: offset - lastNewline - 1,
  };
}

function matchEdits(
  content: string,
  edits: EditToolInput["edits"],
  file: string,
): MatchedEdit[] {
  if (edits.length === 0) {
    throw new Error(
      "Suggest edit input is invalid. edits must contain at least one replacement.",
    );
  }

  const matches = edits.map((edit, editIndex) => {
    const oldText = normalizeToLf(edit.oldText);
    if (oldText.length === 0) {
      throw new Error(
        `edits[${editIndex}].oldText must not be empty in ${file}.`,
      );
    }

    const start = content.indexOf(oldText);
    if (start === -1) {
      throw new Error(
        `Could not find edits[${editIndex}] in ${file}. The oldText must match exactly including all whitespace and newlines.`,
      );
    }
    if (content.indexOf(oldText, start + 1) !== -1) {
      throw new Error(
        `Found multiple occurrences of edits[${editIndex}] in ${file}. Each oldText must be unique. Please provide more context to make it unique.`,
      );
    }

    return {
      editIndex,
      start,
      end: start + oldText.length,
      newText: normalizeToLf(edit.newText),
    };
  });

  const sorted = [...matches].sort((a, b) => a.start - b.start);
  for (let i = 1; i < sorted.length; i++) {
    const previous = sorted[i - 1];
    const current = sorted[i];
    if (previous.end > current.start) {
      throw new Error(
        `edits[${previous.editIndex}] and edits[${current.editIndex}] overlap in ${file}. Merge them into one edit or target disjoint regions.`,
      );
    }
  }

  return matches;
}

function normalizePath(file: string) {
  try {
    return fs.realpathSync(file);
  } catch {
    return path.resolve(file);
  }
}

export default function suggestEdit(pi: ExtensionAPI) {
  pi.registerTool({
    name: "suggest_edit",
    label: "Suggest Edit",
    description:
      "Suggest edits to a single file using the same exact-text replacement interface as edit. This publishes editor-visible quickfixes without modifying the file. Every edits[].oldText must match a unique, non-overlapping region of the original file.",
    promptSnippet:
      "Propose non-invasive editor quickfixes using the same { path, edits } interface as edit",
    promptGuidelines: [
      "Use suggest_edit instead of edit when the user asks for proposed, reviewable, or non-invasive changes.",
      "When suggesting multiple separate locations in one file, use one suggest_edit call with multiple entries in edits[].",
    ],
    parameters: editDefinition.parameters,
    prepareArguments: editDefinition.prepareArguments,
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const input = params as EditToolInput;
      const file = resolveFile(ctx.cwd, input.path);
      const rawContent = fs.readFileSync(file, "utf8");
      const content = normalizeToLf(
        rawContent.startsWith("\uFEFF") ? rawContent.slice(1) : rawContent,
      );
      const matches = matchEdits(content, input.edits, input.path)
        .filter(
          (match) => content.slice(match.start, match.end) !== match.newText,
        )
        .sort((a, b) => a.start - b.start);
      if (matches.length === 0) {
        throw new Error(
          `No changes suggested for ${input.path}. The replacements produced identical content.`,
        );
      }

      const edits = matches.map((match) => ({
        replacement: match.newText,
        range: {
          start: lspPosition(content, match.start),
          end: lspPosition(content, match.end),
        },
      }));
      const firstEdit = edits[0];
      const count = edits.length;
      const suggestion = {
        id: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
        file,
        title:
          count === 1
            ? "Apply suggested edit"
            : `Apply ${count} suggested edits`,
        message:
          count === 1 ? "LLM suggested edit" : `LLM suggested ${count} edits`,
        severity: 3,
        range: firstEdit.range,
        edits,
        createdAt: new Date().toISOString(),
      } satisfies Suggestion;

      writeSuggestions([...readSuggestions(), suggestion]);

      return {
        content: [
          {
            type: "text",
            text: `Published 1 LLM suggestion containing ${count} edit(s) for ${path.relative(ctx.cwd, file)}.`,
          },
        ],
        details: { file, ids: [suggestion.id] },
      };
    },
  });

  pi.registerTool({
    name: "clear_suggested_edits",
    label: "Clear Suggested Edits",
    description: "Clear LLM editor suggestions, optionally only for one file.",
    parameters: {
      type: "object",
      properties: {
        file: {
          type: "string",
          description: "Optional file whose suggestions should be cleared.",
        },
      },
      additionalProperties: false,
    },
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const p = params as ClearParams;
      const before = readSuggestions();
      const after = p.file
        ? before.filter(
            (item) =>
              normalizePath(item.file) !==
              normalizePath(resolveFile(ctx.cwd, p.file!)),
          )
        : [];
      writeSuggestions(after);
      return {
        content: [
          {
            type: "text",
            text: `Cleared ${before.length - after.length} LLM suggested edit(s).`,
          },
        ],
        details: { cleared: before.length - after.length },
      };
    },
  });

  pi.registerCommand("suggest-clear", {
    description: "Clear LLM editor suggestions, optionally for a path",
    handler: async (args: string, ctx: ExtensionCommandContext) => {
      const before = readSuggestions();
      const file = args.trim();
      const after = file
        ? before.filter(
            (item) =>
              normalizePath(item.file) !==
              normalizePath(resolveFile(ctx.cwd, file)),
          )
        : [];
      writeSuggestions(after);
      ctx.ui.notify(
        `Cleared ${before.length - after.length} LLM suggested edit(s)`,
        "info",
      );
    },
  });
}
