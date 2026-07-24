import { readFile, readdir } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

export const USER_AGENT = "m7-osrs-mcp/0.1 (https://m7.rs)";
export const ACCOUNT_DIRECTORY =
  process.env.OSRS_ACCOUNT_EXPORT_DIRECTORY ??
  join(homedir(), ".runelite/account-data-exporter");
export const PROFILES_PATH =
  process.env.RUNELITE_PROFILES_PATH ?? join(homedir(), ".runelite/profiles2");

const headers = { "User-Agent": USER_AGENT, Accept: "application/json" };
const STALE_AFTER_SECONDS = 60;
const MAP_AREAS = [
  ["Grand Exchange", 3150, 3195, 3470, 3515],
  ["Lumbridge", 3190, 3265, 3180, 3265],
  ["Draynor Village", 3070, 3135, 3210, 3290],
  ["Port Sarim", 2990, 3075, 3160, 3255],
  ["Al Kharid", 3265, 3335, 3130, 3320],
  ["Varrock", 3135, 3295, 3370, 3530],
  ["Edgeville", 3060, 3135, 3470, 3525],
  ["Falador", 2940, 3070, 3280, 3400],
  ["Burthorpe", 2870, 2955, 3520, 3595],
  ["Taverley", 2870, 2955, 3390, 3520],
  ["Catherby", 2780, 2865, 3400, 3465],
  ["Seers' Village", 2680, 2760, 3450, 3515],
  ["Ardougne", 2490, 2675, 3250, 3345],
  ["Yanille", 2520, 2625, 3060, 3135],
  ["Tree Gnome Stronghold", 2400, 2505, 3380, 3520],
  ["Rellekka", 2610, 2725, 3620, 3715],
  ["Canifis", 3450, 3525, 3450, 3525],
  ["Prifddinas", 2150, 2305, 3250, 3405],
  ["Ape Atoll", 2680, 2825, 2680, 2825],
  ["Fossil Island", 3600, 3900, 3700, 4000],
  ["Karamja", 2750, 2985, 2800, 3200],
  ["Wilderness", 2940, 3400, 3520, 3970],
  ["Morytania", 3400, 3800, 3000, 3700],
  ["Great Kourend", 1200, 2100, 3400, 4100],
  ["Varlamore", 1200, 2100, 2750, 3400],
  ["Tirannwn", 2100, 2400, 3000, 3600],
  ["Kandarin", 2350, 2900, 3000, 3800],
  ["Asgarnia", 2800, 3100, 3150, 3700],
  ["Misthalin", 3050, 3400, 3100, 3550],
];
let itemMapping;

export async function loadAccount(player, directory = ACCOUNT_DIRECTORY) {
  if (!/^[A-Za-z0-9 _-]{1,12}$/.test(player)) {
    throw new Error(`Invalid OSRS player name: ${player}`);
  }
  const path = join(directory, `${player}.json`);
  let raw;
  try {
    raw = await readFile(path, "utf8");
  } catch (error) {
    throw new Error(
      `RuneLite account export is unavailable at ${path}. Start RuneLite with Account Data Exporter enabled and log into ${player}. (${error.message})`,
    );
  }

  const account = JSON.parse(raw);
  if (!account.timestampIso || !account.skills || !account.quests) {
    throw new Error(
      `RuneLite account export at ${path} has an unsupported shape.`,
    );
  }
  if (account.rsn?.toLowerCase() !== player.toLowerCase()) {
    throw new Error(
      `RuneLite account export belongs to ${account.rsn ?? "an unknown account"}, not ${player}.`,
    );
  }
  return account;
}

export function freshness(account, now = Date.now()) {
  const timestamp = Date.parse(account.timestampIso);
  const ageSeconds = Number.isFinite(timestamp)
    ? Math.max(0, Math.round((now - timestamp) / 1000))
    : null;
  const stale = ageSeconds === null || ageSeconds > STALE_AFTER_SECONDS;
  return {
    timestampIso: account.timestampIso,
    ageSeconds,
    snapshotStatus: stale ? "STALE" : "CURRENT",
    stale,
    gameState: stale ? "STALE_SNAPSHOT" : account.gameState,
    recordedGameState: account.gameState,
    ...(stale
      ? {
          warning:
            "This is an old RuneLite snapshot; recorded login state, location, inventory, and combat context may no longer be current.",
        }
      : {}),
  };
}

export function resolveMapArea(location) {
  if (location?.loaded !== true) return null;
  const { worldX: x, worldY: y } = location;
  if (!Number.isFinite(x) || !Number.isFinite(y)) return null;
  return (
    MAP_AREAS.find(
      ([, minX, maxX, minY, maxY]) =>
        x >= minX && x <= maxX && y >= minY && y <= maxY,
    )?.[0] ?? null
  );
}

function compactValue(value) {
  if (value === null || value === undefined || value === false || value === 0) {
    return undefined;
  }
  if (typeof value === "string" && value.length === 0) return undefined;
  if (Array.isArray(value)) {
    const compacted = value
      .map((entry) => compactValue(entry))
      .filter((entry) => entry !== undefined);
    return compacted.length > 0 ? compacted : undefined;
  }
  if (typeof value === "object") {
    const compacted = Object.fromEntries(
      Object.entries(value)
        .map(([key, entry]) => [key, compactValue(entry)])
        .filter(([, entry]) => entry !== undefined),
    );
    return Object.keys(compacted).length > 0 ? compacted : undefined;
  }
  return value;
}

export function compactSlayer(slayer) {
  return compactValue(slayer);
}

export function sectionMeta(section) {
  if (!section || typeof section !== "object") {
    return {
      available: false,
      contentsCurrent: false,
      absenceMeaning: "unknown_section_unavailable",
    };
  }
  const contentsCurrent = section.loaded === true && section.fromCache !== true;
  return {
    available: true,
    loaded: section.loaded,
    fromCache: section.fromCache,
    lastSeenTimestamp: section.lastSeenTimestamp,
    contentsCurrent,
    absenceMeaning: contentsCurrent
      ? "not_present_in_current_snapshot"
      : "unknown_section_not_current",
  };
}

export function accountSummary(account, { includeRaw = false } = {}) {
  const diaries = account.achievementDiaries ?? {};
  const achievements = account.combatAchievements ?? {};
  const slayer = includeRaw ? account.slayer : compactSlayer(account.slayer);
  return {
    freshness: freshness(account),
    identity: {
      rsn: account.rsn,
      accountType: account.accountTypeName,
      combatLevel: account.combatLevel,
      totalLevel: account.totalLevel,
      totalXp: account.totalXp,
      world: account.world,
    },
    quests: {
      questPoints: account.quests.questPoints,
      finished: account.quests.finished,
      inProgress: account.quests.inProgress,
      notStarted: account.quests.notStarted,
      total: account.quests.total,
    },
    achievementDiaries: {
      completedTiers: diaries.completedTierCount,
      totalTiers: diaries.totalTierCount,
      completionPercent: diaries.completionPercent,
    },
    combatAchievements: {
      completed: achievements.completed,
      total: achievements.total,
      tiers: achievements.tiers?.map(({ name, completed, total }) => ({
        name,
        completed,
        total,
      })),
    },
    ...(slayer === undefined ? {} : { slayer }),
    wealth: {
      knownAccountValue: account.knownAccountValue,
      grandExchangeEstimate: account.grandExchangeAccountValueEstimate,
      knownAccountValueWithGeEstimate: account.knownAccountValueWithGeEstimate,
    },
    dataAvailability: Object.fromEntries(
      [
        "bank",
        "inventory",
        "equipment",
        "seedVault",
        "lootingBag",
        "grandExchange",
        "location",
      ].map((name) => [name, sectionMeta(account[name])]),
    ),
  };
}

export function filterSkills(account, names = []) {
  const wanted = names.map((name) => name.toLowerCase());
  return Object.fromEntries(
    Object.entries(account.skills).filter(
      ([name]) => wanted.length === 0 || wanted.includes(name.toLowerCase()),
    ),
  );
}

export function filterQuests(account, states = [], query) {
  const wantedStates = states.map((state) => state.toUpperCase());
  const needle = query?.toLowerCase();
  return account.quests.entries.filter(
    (quest) =>
      (wantedStates.length === 0 || wantedStates.includes(quest.state)) &&
      (!needle || quest.name.toLowerCase().includes(needle)),
  );
}

export function findItems(account, query, containers) {
  const needle = query.toLowerCase();
  return containers.map((container) => {
    const section = account[container];
    const matches = (section?.items ?? []).filter((item) =>
      item.name.toLowerCase().includes(needle),
    );
    return {
      container,
      ...sectionMeta(section),
      itemCount: section?.itemCount,
      value: section?.value,
      matches,
    };
  });
}

export function combatAchievements(account, { tier, completed, query, limit }) {
  const needle = query?.toLowerCase();
  let remaining = limit;
  let matchedTaskCount = 0;
  let returnedTaskCount = 0;
  const tiers = (account.combatAchievements?.tiers ?? [])
    .filter((entry) => !tier || entry.name.toLowerCase() === tier.toLowerCase())
    .map((entry) => {
      let tasks = entry.tasks ?? [];
      if (completed !== undefined) {
        tasks = tasks.filter((task) => task.completed === completed);
      }
      if (needle) {
        tasks = tasks.filter((task) =>
          task.name.toLowerCase().includes(needle),
        );
      }
      const matchedInTier = tasks.length;
      const returned = tasks.slice(0, remaining);
      remaining -= returned.length;
      matchedTaskCount += matchedInTier;
      returnedTaskCount += returned.length;
      return {
        name: entry.name,
        completed: entry.completed,
        total: entry.total,
        tasks: returned,
        matchedTaskCount: matchedInTier,
      };
    });
  return {
    completed: account.combatAchievements?.completed,
    total: account.combatAchievements?.total,
    matchedTaskCount,
    returnedTaskCount,
    tiers,
  };
}

export async function fetchJson(url) {
  const response = await fetch(url, {
    headers,
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) {
    throw new Error(`${response.status} ${response.statusText} from ${url}`);
  }
  const maxBytes = 10 * 1024 * 1024;
  const contentLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(contentLength) && contentLength > maxBytes) {
    throw new Error(`Response from ${url} exceeds ${maxBytes} bytes.`);
  }
  const body = await response.text();
  if (Buffer.byteLength(body) > maxBytes) {
    throw new Error(`Response from ${url} exceeds ${maxBytes} bytes.`);
  }
  return JSON.parse(body);
}

function meaningfulHiscore(entry) {
  if (typeof entry.xp === "number") return entry.xp > 0;
  if (typeof entry.score === "number") return entry.score > 0;
  return Object.entries(entry).some(
    ([key, value]) =>
      !["id", "name", "rank"].includes(key) &&
      typeof value === "number" &&
      value > 0,
  );
}

export function compactHiscores(hiscores) {
  return Object.fromEntries(
    Object.entries(hiscores).flatMap(([key, value]) => {
      if (!Array.isArray(value)) return [[key, value]];
      const entries = value.filter(meaningfulHiscore);
      return entries.length > 0 ? [[key, entries]] : [];
    }),
  );
}

export async function fetchHiscores(player, { includeRaw = false } = {}) {
  const url = new URL(
    "https://secure.runescape.com/m=hiscore_oldschool/index_lite.json",
  );
  url.searchParams.set("player", player);
  const hiscores = await fetchJson(url);
  return includeRaw ? hiscores : compactHiscores(hiscores);
}

export async function wikiSearch(query, limit) {
  const url = new URL("https://oldschool.runescape.wiki/api.php");
  url.search = new URLSearchParams({
    action: "query",
    list: "search",
    srsearch: query,
    srlimit: String(limit),
    srprop: "snippet|sectiontitle",
    format: "json",
    formatversion: "2",
  });
  const data = await fetchJson(url);
  return data.query.search.map(({ title, snippet, sectiontitle }) => ({
    title,
    sectiontitle,
    snippet: snippet.replace(/<[^>]+>/g, ""),
    url: `https://oldschool.runescape.wiki/w/${encodeURIComponent(
      title.replaceAll(" ", "_"),
    )}`,
  }));
}

export async function wikiPage(title, maxCharacters) {
  const url = new URL("https://oldschool.runescape.wiki/api.php");
  url.search = new URLSearchParams({
    action: "query",
    prop: "extracts|info",
    titles: title,
    explaintext: "1",
    redirects: "1",
    inprop: "url",
    format: "json",
    formatversion: "2",
  });
  const data = await fetchJson(url);
  const page = data.query.pages[0];
  if (page.missing) throw new Error(`OSRS Wiki page not found: ${title}`);
  const extract = page.extract ?? "";
  return {
    title: page.title,
    url: page.fullurl,
    extract: extract.slice(0, maxCharacters),
    truncated: extract.length > maxCharacters,
    totalCharacters: extract.length,
  };
}

async function getItemMapping() {
  itemMapping ??= fetchJson(
    "https://prices.runescape.wiki/api/v1/osrs/mapping",
  );
  return itemMapping;
}

export async function itemPrices(query, limit) {
  const needle = query.toLowerCase();
  const mapping = (await getItemMapping())
    .filter((item) => item.name.toLowerCase().includes(needle))
    .slice(0, limit);
  const latest = await fetchJson(
    "https://prices.runescape.wiki/api/v1/osrs/latest",
  );
  return mapping.map((item) => ({
    id: item.id,
    name: item.name,
    examine: item.examine,
    members: item.members,
    buyLimit: item.limit,
    value: item.value,
    alch: { high: item.highalch, low: item.lowalch },
    market: latest.data[String(item.id)] ?? null,
  }));
}

function decodeJavaProperty(value) {
  return value.replace(/\\(u[0-9a-fA-F]{4}|n|r|t|f|.)/g, (_, escape) => {
    if (escape.startsWith("u")) {
      return String.fromCharCode(Number.parseInt(escape.slice(1), 16));
    }
    return { n: "\n", r: "\r", t: "\t", f: "\f" }[escape] ?? escape;
  });
}

export async function readRuneLiteNotes(
  directory = PROFILES_PATH,
  maxCharacters = 10_000,
) {
  const files = (await readdir(directory)).filter((name) =>
    name.endsWith(".properties"),
  );
  const notes = [];
  for (const file of files) {
    const content = await readFile(join(directory, file), "utf8");
    const lines = content.match(/(?:^|\n)notes\.notesData=(.*(?:\\\n.*)*)/);
    if (lines) {
      const fullText = decodeJavaProperty(lines[1]);
      notes.push({
        profile: file,
        text: fullText.slice(0, maxCharacters),
        truncated: fullText.length > maxCharacters,
        totalCharacters: fullText.length,
      });
    }
  }
  return notes;
}
