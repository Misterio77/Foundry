#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import * as z from "zod/v4";
import {
  accountSummary,
  combatAchievements,
  compactSlayer,
  fetchHiscores,
  filterQuests,
  filterSkills,
  findItems,
  freshness,
  itemPrices,
  loadAccount,
  readRuneLiteNotes,
  resolveMapArea,
  sectionMeta,
  wikiPage,
  wikiSearch,
} from "./lib.mjs";

const server = new McpServer({ name: "osrs", version: "0.1.0" });
const text = (value) => ({
  content: [
    {
      type: "text",
      text: typeof value === "string" ? value : JSON.stringify(value, null, 2),
    },
  ],
});
const tool = (name, options, handler) =>
  server.registerTool(name, options, async (args) => {
    try {
      return text(await handler(args));
    } catch (error) {
      return {
        ...text(
          `Error: ${error instanceof Error ? error.message : String(error)}`,
        ),
        isError: true,
      };
    }
  });

const itemContainers = [
  "bank",
  "inventory",
  "equipment",
  "seedVault",
  "lootingBag",
  "seedBox",
  "tackleBox",
  "forestryKit",
  "huntsmansKit",
];
const playerSchema = z
  .string()
  .min(1)
  .max(12)
  .regex(/^[A-Za-z0-9 _-]+$/)
  .describe(
    "OSRS display name whose local export or Hiscores entry should be read.",
  );

tool(
  "account_summary",
  {
    description:
      "Read a player's RuneLite snapshot and summarize account identity, freshness, quests, diaries, Combat Achievements, meaningful Slayer state, wealth, and which private sections are loaded. Old snapshots are explicitly marked stale. Call this before giving account-specific progression advice.",
    inputSchema: {
      player: playerSchema,
      includeRaw: z
        .boolean()
        .default(false)
        .describe("Include empty and zero-only raw Slayer data."),
    },
  },
  async ({ player, includeRaw }) =>
    accountSummary(await loadAccount(player), { includeRaw }),
);

tool(
  "skills",
  {
    description:
      "Read current OSRS skill levels, boosted levels, and XP from a player's RuneLite snapshot. Returns every skill unless names are supplied.",
    inputSchema: {
      player: playerSchema,
      names: z
        .array(z.string())
        .optional()
        .describe('Exact skill names, for example ["Prayer", "Ranged"].'),
    },
  },
  async ({ player, names = [] }) => {
    const account = await loadAccount(player);
    return {
      freshness: freshness(account),
      skills: filterSkills(account, names),
    };
  },
);

tool(
  "quests",
  {
    description:
      "Read a player's live quest completion state. Filter unfinished quests for Quest Point Cape planning or look up a named quest.",
    inputSchema: {
      player: playerSchema,
      states: z
        .array(z.enum(["FINISHED", "IN_PROGRESS", "NOT_STARTED", "UNKNOWN"]))
        .optional()
        .describe("Quest states to include; omit for all."),
      query: z
        .string()
        .optional()
        .describe("Case-insensitive quest-name substring."),
    },
  },
  async ({ player, states = [], query }) => {
    const account = await loadAccount(player);
    return {
      freshness: freshness(account),
      summary: {
        questPoints: account.quests.questPoints,
        finished: account.quests.finished,
        inProgress: account.quests.inProgress,
        notStarted: account.quests.notStarted,
        total: account.quests.total,
      },
      quests: filterQuests(account, states, query),
    };
  },
);

tool(
  "find_items",
  {
    description:
      "Search a player's bank, inventory, equipment, and auxiliary containers by item name. Includes loaded/cache timestamps so absence is not mistaken for non-ownership.",
    inputSchema: {
      player: playerSchema,
      query: z
        .string()
        .min(1)
        .describe("Case-insensitive item-name substring."),
      containers: z
        .array(z.enum(itemContainers))
        .optional()
        .describe(
          "Containers to search; defaults to all supported containers.",
        ),
    },
  },
  async ({ player, query, containers = itemContainers }) => {
    const account = await loadAccount(player);
    return {
      freshness: freshness(account),
      results: findItems(account, query, containers),
    };
  },
);

tool(
  "live_state",
  {
    description:
      "Read current coordinates and their named map area, status, combat state, animation, inventory, and equipment from RuneLite for contextual play assistance. Old snapshots are explicitly marked stale. Read-only; never controls gameplay.",
    inputSchema: {
      player: playerSchema,
      includeItems: z
        .boolean()
        .default(true)
        .describe("Include inventory and equipment item lists."),
    },
  },
  async ({ player, includeItems }) => {
    const account = await loadAccount(player);
    const summarizeContainer = (name) => ({
      ...sectionMeta(account[name]),
      itemCount: account[name]?.itemCount,
      value: account[name]?.value,
      ...(includeItems ? { items: account[name]?.items ?? [] } : {}),
    });
    return {
      freshness: freshness(account),
      world: account.world,
      location: {
        ...account.location,
        mapArea: resolveMapArea(account.location),
      },
      status: account.status,
      combat: account.combat,
      animation: account.animation,
      inventory: summarizeContainer("inventory"),
      equipment: summarizeContainer("equipment"),
    };
  },
);

tool(
  "progression",
  {
    description:
      "Read detailed Achievement Diary, Combat Achievement, Slayer, or Grand Exchange progression from a player's RuneLite snapshot. Combat Achievement task output is bounded and filterable.",
    inputSchema: {
      player: playerSchema,
      section: z.enum([
        "achievement_diaries",
        "combat_achievements",
        "slayer",
        "grand_exchange",
      ]),
      tier: z.string().optional().describe("Combat Achievement tier name."),
      completed: z
        .boolean()
        .optional()
        .describe("Filter Combat Achievement tasks."),
      query: z
        .string()
        .optional()
        .describe("Combat Achievement task-name substring."),
      limit: z
        .number()
        .int()
        .min(1)
        .max(200)
        .default(50)
        .describe("Maximum Combat Achievement tasks across all tiers."),
      includeRaw: z
        .boolean()
        .default(false)
        .describe("Include empty and zero-only raw Slayer data."),
    },
  },
  async ({ player, section, tier, completed, query, limit, includeRaw }) => {
    const account = await loadAccount(player);
    const data = {
      achievement_diaries: account.achievementDiaries,
      combat_achievements: combatAchievements(account, {
        tier,
        completed,
        query,
        limit,
      }),
      slayer: includeRaw ? account.slayer : compactSlayer(account.slayer),
      grand_exchange: account.grandExchange,
    }[section];
    return { freshness: freshness(account), section, data };
  },
);

tool(
  "hiscores",
  {
    description:
      "Fetch public official OSRS Hiscores JSON for a player's meaningful skills, activities, and ranked boss kill counts. Empty, zero-only, and unranked entries are omitted by default. This source works even when RuneLite is closed.",
    inputSchema: {
      player: playerSchema,
      includeRaw: z
        .boolean()
        .default(false)
        .describe("Return every raw Hiscores entry, including empty ones."),
    },
  },
  async ({ player, includeRaw }) => fetchHiscores(player, { includeRaw }),
);

tool(
  "wiki_search",
  {
    description:
      "Search the current Old School RuneScape Wiki for quests, mechanics, training methods, items, bosses, or guides before giving factual game advice.",
    inputSchema: {
      query: z.string().min(1),
      limit: z.number().int().min(1).max(20).default(8),
    },
  },
  async ({ query, limit }) => wikiSearch(query, limit),
);

tool(
  "wiki_page",
  {
    description:
      "Read a current OSRS Wiki page as plain text. Use after wiki_search for requirements, mechanics, methods, and recommendations. Continue truncated pages by passing the returned nextOffset.",
    inputSchema: {
      title: z
        .string()
        .min(1)
        .describe("Exact or redirectable wiki page title."),
      maxCharacters: z.number().int().min(1000).max(50000).default(20000),
      offset: z
        .number()
        .int()
        .min(0)
        .default(0)
        .describe("Character offset; use nextOffset to continue a page."),
    },
  },
  async ({ title, maxCharacters, offset }) =>
    wikiPage(title, maxCharacters, offset),
);

tool(
  "item_prices",
  {
    description:
      "Look up current RuneLite/OSRS Wiki real-time Grand Exchange high and low prices plus alch values and buy limits by item-name substring.",
    inputSchema: {
      query: z.string().min(1),
      limit: z.number().int().min(1).max(25).default(10),
    },
  },
  async ({ query, limit }) => itemPrices(query, limit),
);

tool(
  "runelite_notes",
  {
    description:
      "Read the user-authored RuneLite Notes plugin text from local profiles as an optional player-to-agent message channel.",
    inputSchema: {
      maxCharacters: z.number().int().min(100).max(20_000).default(10_000),
    },
  },
  async ({ maxCharacters }) => readRuneLiteNotes(undefined, maxCharacters),
);

await server.connect(new StdioServerTransport());
