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
  discoverPlayers,
  filterQuests,
  filterSkills,
  findItems,
  freshness,
  loadAccount,
  normalizeMarket,
  paginateText,
  rankWikiResults,
  readRuneLiteNotes,
  resolveMapArea,
  roundPercentages,
  sectionMeta,
  timestampToIso,
  unresolvedMapAreaReason,
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
    completionPercent: 35.416666666666664,
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
    lastSeenTimestamp: 1_700_000_000_000,
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

test("deduplicates and normalizes local account lookups", async () => {
  const directory = await mkdtemp(join(tmpdir(), "osrs-mcp-"));
  await writeFile(join(directory, "Test User.json"), JSON.stringify(account));
  await writeFile(
    join(directory, "latest.json"),
    JSON.stringify({
      ...account,
      timestampIso: "2020-01-01T00:00:00.000Z",
      totalLevel: 100,
    }),
  );
  await writeFile(join(directory, "broken.json"), "{");
  await writeFile(
    join(directory, "invalid-time.json"),
    JSON.stringify({
      ...account,
      timestampIso: "eventually",
      totalLevel: 9999,
    }),
  );
  await writeFile(join(directory, "ignore.txt"), "not an export");

  assert.equal((await loadAccount("test_user", directory)).rsn, "Test User");
  const players = await discoverPlayers(directory);
  assert.equal(players.length, 1);
  assert.equal(players[0].player, "Test User");
  assert.equal(players[0].totalLevel, 1500);

  await assert.rejects(
    loadAccount("Missing", directory),
    (error) =>
      error.message.includes("No local RuneLite account export found") &&
      !error.message.includes(directory),
  );
});

test("summarizes without item lists or empty Slayer data", () => {
  const summary = accountSummary(account);
  assert.equal(summary.identity.rsn, "Test User");
  assert.equal(summary.quests.questPoints, 200);
  assert.equal(summary.dataAvailability.bank.loaded, true);
  assert.equal("items" in summary.dataAvailability.bank, false);
  assert.equal(summary.achievementDiaries.completionPercent, 35.42);
  assert.equal("slayer" in summary, false);
  assert.deepEqual(
    accountSummary(account, { includeRawSlayer: true }).slayer,
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
  assert.equal(
    freshness(
      {
        timestampIso: "2026-01-01T01:00:00.000+01:00",
        gameState: "LOGGED_IN",
      },
      Date.parse("2026-01-01T00:00:00.000Z"),
    ).timestampIso,
    "2026-01-01T00:00:00.000Z",
  );
});

test("resolves coordinates to the most specific named map area", () => {
  assert.equal(
    resolveMapArea({
      loaded: true,
      worldX: 3184,
      worldY: 2455,
      regionId: 12582,
    }),
    "The Great Conch",
  );
  assert.equal(
    resolveMapArea({ loaded: true, worldX: 3222, worldY: 3218 }),
    "Lumbridge",
  );
  assert.equal(
    resolveMapArea({ loaded: true, worldX: 3165, worldY: 3490 }),
    "Grand Exchange",
  );
  const unresolved = {
    loaded: true,
    worldX: 10_000,
    worldY: 10_000,
    regionId: 99_999,
  };
  assert.equal(resolveMapArea(unresolved), null);
  assert.equal(
    unresolvedMapAreaReason(unresolved),
    "No named map area mapping is available for region 99999.",
  );
  assert.equal(resolveMapArea({ loaded: false }), null);
  assert.equal(
    unresolvedMapAreaReason({ loaded: false }),
    "RuneLite did not provide a loaded location.",
  );
});

test("compacts zero-only Slayer and Hiscores data", () => {
  assert.equal(compactSlayer(account.slayer), undefined);
  assert.deepEqual(
    compactSlayer({
      ...account.slayer,
      superiorCreaturesDefeated: 3,
      blocks: [
        { slot: 1, monster: "", active: false },
        { slot: 2, monster: "Abyssal demon", active: true },
      ],
    }),
    {
      superiorCreaturesDefeated: 3,
      blocks: [{ slot: 2, monster: "Abyssal demon", active: true }],
    },
  );
  const raw = {
    skills: [
      { id: 0, name: "Overall", rank: 1, level: 1500, xp: 12_345_678 },
      { id: 1, name: "Attack", rank: -1, level: 10, xp: 1_154 },
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

test("ranks canonical Wiki titles above incidental subpage matches", () => {
  const incidental = { title: "Demonic Pacts League/Areas/Morytania" };
  const canonical = { title: "Hallowed Sepulchre" };
  assert.deepEqual(
    rankWikiResults(
      "Hallowed Sepulchre agility requirements",
      [incidental, canonical, { title: "Agility" }],
      3,
    )[0],
    canonical,
  );
});

test("rounds percentage fields recursively", () => {
  assert.deepEqual(
    roundPercentages({
      completionPercent: 35.416666666666664,
      tiers: [{ completionPercent: 1.2345 }],
      exactValue: 1.2345,
    }),
    {
      completionPercent: 35.42,
      tiers: [{ completionPercent: 1.23 }],
      exactValue: 1.2345,
    },
  );
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

test("normalizes snapshot-adjacent timestamps and section metadata", () => {
  assert.equal(timestampToIso(1_700_000_000), "2023-11-14T22:13:20.000Z");
  assert.equal(timestampToIso(1_700_000_000_000), "2023-11-14T22:13:20.000Z");
  assert.deepEqual(sectionMeta(account.bank), {
    available: true,
    loaded: true,
    fromCache: false,
    lastSeenTimestampIso: "2023-11-14T22:13:20.000Z",
    currentAtSnapshot: true,
    absenceMeaning: "not_present_at_snapshot",
  });
  assert.deepEqual(
    normalizeMarket({ high: 100, highTime: 1_700_000_000, lowTime: null }),
    {
      high: 100,
      highTimeIso: "2023-11-14T22:13:20.000Z",
      lowTimeIso: undefined,
    },
  );
});

test("filters skills and quest state case-insensitively", () => {
  assert.deepEqual(Object.keys(filterSkills(account, ["prayer"])), ["Prayer"]);
  assert.deepEqual(filterQuests(account, ["NOT_STARTED"], "ransom"), [
    account.quests.entries[0],
  ]);
});

test("item searches compact empty containers but summarize the search", () => {
  const result = findItems(account, "dragon", ["bank", "inventory"]);
  assert.equal(result.results.length, 1);
  assert.equal(result.results[0].matches.length, 2);
  assert.equal(result.results[0].loaded, true);
  assert.deepEqual(
    result.searchedContainers.map(({ container, matchCount }) => ({
      container,
      matchCount,
    })),
    [
      { container: "bank", matchCount: 2 },
      { container: "inventory", matchCount: 0 },
    ],
  );
  assert.equal(
    findItems(account, "dragon", ["bank", "inventory"], {
      includeEmptyContainers: true,
    }).results.length,
    2,
  );
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

test("filters and selects RuneLite Notes profiles", async () => {
  const directory = await mkdtemp(join(tmpdir(), "osrs-notes-"));
  await writeFile(
    join(directory, "Main.properties"),
    "other.value=x\nnotes.notesData=HELLO\\nWORLD\\u0021\n",
  );
  await writeFile(join(directory, "Empty.properties"), "notes.notesData=\n");
  const expected = {
    profile: "Main.properties",
    text: "HELLO\nWORLD!",
    truncated: false,
    totalCharacters: 12,
  };
  assert.deepEqual(await readRuneLiteNotes(directory), [expected]);
  assert.deepEqual(
    await readRuneLiteNotes(directory, 10_000, { profile: "main" }),
    [expected],
  );
  assert.equal(
    (
      await readRuneLiteNotes(directory, 10_000, {
        profile: "Empty.properties",
        includeEmpty: true,
      })
    ).length,
    1,
  );

  const missing = join(directory, "missing");
  await assert.rejects(
    readRuneLiteNotes(missing),
    (error) =>
      error.message === "RuneLite Notes profiles are unavailable." &&
      !error.message.includes(missing),
  );
});
