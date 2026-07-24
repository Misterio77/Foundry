import assert from "node:assert/strict";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  accountSummary,
  combatAchievements,
  filterQuests,
  filterSkills,
  findItems,
  loadAccount,
  readRuneLiteNotes,
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

test("summarizes without copying item lists", () => {
  const summary = accountSummary(account);
  assert.equal(summary.identity.rsn, "Test User");
  assert.equal(summary.quests.questPoints, 200);
  assert.equal(summary.dataAvailability.bank.loaded, true);
  assert.equal("items" in summary.dataAvailability.bank, false);
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

test("combat achievement output is filtered and bounded", () => {
  const result = combatAchievements(account, {
    tier: "easy",
    completed: false,
    query: "task",
    limit: 1,
  });
  assert.equal(result.tiers[0].matchedTaskCount, 1);
  assert.equal(result.tiers[0].tasks[0].name, "Another task");
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
