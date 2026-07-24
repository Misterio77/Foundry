import assert from "node:assert/strict";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  accountSummary,
  combatAchievements,
  compactHiscores,
  compactSlayer,
  filterQuests,
  filterSkills,
  findItems,
  freshness,
  loadAccount,
  paginateText,
  readRuneLiteNotes,
  resolveMapArea,
} from "../lib.mjs";

const account = {
  timestampIso: new Date().toISOString(),
  gameState: "LOGGED_IN",
  rsn: "Test User",
  accountTypeName: "Normal",
  combatLevel: 99,
  totalLevel: 1500,
  totalXp: 12_345_678,
  world: 420,
  skills: {
    Attack: { level: 75, boostedLevel: 75, xp: 1_210_421 },
    Prayer: { level: 60, boostedLevel: 65, xp: 273_742 },
  },
  quests: {
    questPoints: 200,
    finished: 100,
    inProgress: 1,
    notStarted: 20,
    total: 121,
    entries: [
      { id: "KINGS_RANSOM", name: "King's Ransom", state: "NOT_STARTED" },
      { id: "COOKS_ASSISTANT", name: "Cook's Assistant", state: "FINISHED" },
    ],
  },
  achievementDiaries: {
    completedTierCount: 2,
    totalTierCount: 48,
    completionPercent: 4.2,
  },
  combatAchievements: {
    completed: 1,
    total: 2,
    tiers: [
      {
        name: "Easy",
        completed: 1,
        total: 2,
        tasks: [
          { id: 1, name: "Easy does it", completed: true },
          { id: 2, name: "Another task", completed: false },
        ],
      },
      {
        name: "Medium",
        completed: 0,
        total: 1,
        tasks: [{ id: 3, name: "Medium task", completed: false }],
      },
    ],
  },
  slayer: {
    points: 0,
    tasksCompletedStreak: 0,
    currentTask: { hasTask: false },
  },
  bank: {
    loaded: true,
    fromCache: false,
    lastSeenTimestamp: 42,
    itemCount: 2,
    value: 1000,
    items: [
      { id: 1, name: "Dragon defender", quantity: 1, value: 0 },
      { id: 2, name: "Dragon dagger", quantity: 2, value: 1000 },
    ],
  },
  inventory: { loaded: false, items: [] },
  equipment: { loaded: true, items: [] },
};

test("loads and validates an account export", async () => {
  const directory = await mkdtemp(join(tmpdir(), "osrs-mcp-"));
  const path = join(directory, "Test User.json");
  await writeFile(path, JSON.stringify(account));
  assert.equal((await loadAccount("Test User", directory)).rsn, "Test User");
});

test("summarizes without item lists or empty Slayer data", () => {
  const summary = accountSummary(account);
  assert.equal(summary.identity.rsn, "Test User");
  assert.equal(summary.quests.questPoints, 200);
  assert.equal(summary.dataAvailability.bank.loaded, true);
  assert.equal("items" in summary.dataAvailability.bank, false);
  assert.equal("slayer" in summary, false);
  assert.deepEqual(
    accountSummary(account, { includeRaw: true }).slayer,
    account.slayer,
  );
});

test("marks old snapshots stale instead of reporting a current login", () => {
  const result = freshness(
    { timestampIso: "2026-01-01T00:00:00.000Z", gameState: "LOGGED_IN" },
    Date.parse("2026-01-01T00:02:00.000Z"),
  );
  assert.equal(result.snapshotStatus, "STALE");
  assert.equal(result.gameState, "STALE_SNAPSHOT");
  assert.equal(result.recordedGameState, "LOGGED_IN");
});

test("resolves coordinates to the most specific named map area", () => {
  assert.equal(
    resolveMapArea({ loaded: true, worldX: 3222, worldY: 3218 }),
    "Lumbridge",
  );
  assert.equal(
    resolveMapArea({ loaded: true, worldX: 3165, worldY: 3490 }),
    "Grand Exchange",
  );
  assert.equal(
    resolveMapArea({ loaded: true, worldX: 10_000, worldY: 10_000 }),
    null,
  );
  assert.equal(resolveMapArea({ loaded: false }), null);
});

test("compacts zero-only Slayer and Hiscores data", () => {
  assert.equal(compactSlayer(account.slayer), undefined);
  assert.deepEqual(
    compactSlayer({ ...account.slayer, superiorCreaturesDefeated: 3 }),
    { superiorCreaturesDefeated: 3 },
  );
  const raw = {
    skills: [
      { id: 0, name: "Overall", rank: 1, level: 1500, xp: 12_345_678 },
      { id: 1, name: "Attack", rank: -1, level: 1, xp: 0 },
    ],
    activities: [
      { id: 0, name: "Clue Scrolls", rank: -1, score: -1 },
      { id: 1, name: "Vorkath", rank: 100, score: 25 },
    ],
    bosses: [{ id: 0, name: "Zulrah", rank: -1, score: -1 }],
  };
  assert.deepEqual(compactHiscores(raw), {
    skills: [raw.skills[0]],
    activities: [raw.activities[1]],
  });
});

test("paginates Wiki extracts with a continuation offset", () => {
  assert.deepEqual(paginateText("abcdef", 2), {
    extract: "ab",
    offset: 0,
    returnedCharacters: 2,
    truncated: true,
    nextOffset: 2,
    continuationHint:
      "Call wiki_page again with the same title and offset=2 to continue.",
    totalCharacters: 6,
  });
  assert.deepEqual(paginateText("abcdef", 2, 4), {
    extract: "ef",
    offset: 4,
    returnedCharacters: 2,
    truncated: false,
    nextOffset: null,
    totalCharacters: 6,
  });
});

test("filters skills and quest state case-insensitively", () => {
  assert.deepEqual(Object.keys(filterSkills(account, ["prayer"])), ["Prayer"]);
  assert.deepEqual(filterQuests(account, ["NOT_STARTED"], "ransom"), [
    account.quests.entries[0],
  ]);
});

test("item searches retain container freshness metadata", () => {
  const [bank, inventory] = findItems(account, "dragon", ["bank", "inventory"]);
  assert.equal(bank.matches.length, 2);
  assert.equal(bank.loaded, true);
  assert.equal(inventory.loaded, false);
});

test("combat achievement output is filtered and globally bounded", () => {
  const filtered = combatAchievements(account, {
    tier: "easy",
    completed: false,
    query: "task",
    limit: 1,
  });
  assert.equal(filtered.tiers[0].matchedTaskCount, 1);
  assert.equal(filtered.tiers[0].tasks[0].name, "Another task");

  const global = combatAchievements(account, { limit: 2 });
  assert.equal(global.matchedTaskCount, 3);
  assert.equal(global.returnedTaskCount, 2);
  assert.equal(global.tiers[0].tasks.length, 2);
  assert.equal(global.tiers[1].tasks.length, 0);
});

test("reads and decodes RuneLite notes without relying on a fixed profile name", async () => {
  const directory = await mkdtemp(join(tmpdir(), "osrs-notes-"));
  await writeFile(
    join(directory, "Main.properties"),
    "other.value=x\nnotes.notesData=HELLO\\nWORLD\\u0021\n",
  );
  assert.deepEqual(await readRuneLiteNotes(directory), [
    {
      profile: "Main.properties",
      text: "HELLO\nWORLD!",
      truncated: false,
      totalCharacters: 12,
    },
  ]);
});
