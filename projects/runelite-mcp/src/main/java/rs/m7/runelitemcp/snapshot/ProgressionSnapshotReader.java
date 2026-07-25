package rs.m7.runelitemcp.snapshot;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.HashSet;
import net.runelite.api.Client;
import net.runelite.api.EnumComposition;
import net.runelite.api.ItemComposition;
import net.runelite.api.Quest;
import net.runelite.api.QuestState;
import net.runelite.api.StructComposition;
import net.runelite.api.gameval.DBTableID;
import net.runelite.api.gameval.VarPlayerID;
import net.runelite.api.gameval.VarbitID;

final class ProgressionSnapshotReader
{
	private static final int PARAM_CA_TASK_NAME = 1308;
	private static final int PARAM_CA_TASK_ID = 1306;
	private static final int[] CA_VARPS = {
		VarPlayerID.CA_TASK_COMPLETED_0, VarPlayerID.CA_TASK_COMPLETED_1,
		VarPlayerID.CA_TASK_COMPLETED_2, VarPlayerID.CA_TASK_COMPLETED_3,
		VarPlayerID.CA_TASK_COMPLETED_4, VarPlayerID.CA_TASK_COMPLETED_5,
		VarPlayerID.CA_TASK_COMPLETED_6, VarPlayerID.CA_TASK_COMPLETED_7,
		VarPlayerID.CA_TASK_COMPLETED_8, VarPlayerID.CA_TASK_COMPLETED_9,
		VarPlayerID.CA_TASK_COMPLETED_10, VarPlayerID.CA_TASK_COMPLETED_11,
		VarPlayerID.CA_TASK_COMPLETED_12, VarPlayerID.CA_TASK_COMPLETED_13,
		VarPlayerID.CA_TASK_COMPLETED_14, VarPlayerID.CA_TASK_COMPLETED_15,
		VarPlayerID.CA_TASK_COMPLETED_16, VarPlayerID.CA_TASK_COMPLETED_17,
		VarPlayerID.CA_TASK_COMPLETED_18, VarPlayerID.CA_TASK_COMPLETED_19
	};
	private static final int[] COLLECTION_RECENT_ITEMS = {
		VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM0, VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM1,
		VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM2, VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM3,
		VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM4, VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM5,
		VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM6, VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM7,
		VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM8, VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM9,
		VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM10, VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM11
	};
	private static final int[] COLLECTION_RECENT_DATES = {
		VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM0_DATE, VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM1_DATE,
		VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM2_DATE, VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM3_DATE,
		VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM4_DATE, VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM5_DATE,
		VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM6_DATE, VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM7_DATE,
		VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM8_DATE, VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM9_DATE,
		VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM10_DATE, VarPlayerID.COLLECTION_OVERVIEW_LAST_ITEM11_DATE
	};
	private static final Map<Integer, String> CA_TIERS;
	private static final String[] SLAYER_MASTERS = {
		null, "Turael", "Mazchna", "Vannaka", "Chaeldar", "Duradel", "Nieve",
		"Krystilia", "Konar quo Maten"
	};

	static
	{
		Map<Integer, String> tiers = new LinkedHashMap<>();
		tiers.put(3981, "Easy");
		tiers.put(3982, "Medium");
		tiers.put(3983, "Hard");
		tiers.put(3984, "Elite");
		tiers.put(3985, "Master");
		tiers.put(3986, "Grandmaster");
		CA_TIERS = Collections.unmodifiableMap(tiers);
	}

	private final Client client;
	private final Map<Integer, List<CombatTask>> combatTasks = new HashMap<>();
	private final Map<Integer, String> slayerTaskNames = new HashMap<>();
	private final Map<Integer, String> slayerAreaNames = new HashMap<>();
	private final Map<Integer, String> slayerBossNames = new HashMap<>();
	private final Set<String> missingSlayerNames = new HashSet<>();

	ProgressionSnapshotReader(Client client)
	{
		this.client = client;
	}

	JsonObject quests(JsonObject arguments)
	{
		Set<String> states = strings(arguments, "states");
		String query = string(arguments, "query");
		int offset = integer(arguments, "offset", 0);
		int limit = integer(arguments, "limit", 50);
		int notStarted = 0;
		int inProgress = 0;
		int finished = 0;
		int unknown = 0;
		List<JsonObject> matching = new ArrayList<>();
		for (Quest quest : Quest.values())
		{
			QuestState state = null;
			try
			{
				state = quest.getState(client);
			}
			catch (RuntimeException ignored)
			{
				// A newly added quest can be unavailable until its game state is loaded.
			}
			String wireState = state == null ? "unknown" : state.name().toLowerCase(Locale.ROOT);
			switch (wireState)
			{
				case "not_started": notStarted++; break;
				case "in_progress": inProgress++; break;
				case "finished": finished++; break;
				default: unknown++;
			}
			if (!states.isEmpty() && !states.contains(wireState)
				|| query != null && !contains(quest.getName(), query) && !contains(quest.name(), query))
			{
				continue;
			}
			JsonObject entry = new JsonObject();
			entry.addProperty("id", quest.name());
			entry.addProperty("name", quest.getName());
			entry.addProperty("state", wireState);
			matching.add(entry);
		}
		JsonObject result = new JsonObject();
		result.addProperty("questPoints", client.getVarpValue(VarPlayerID.QP));
		JsonObject counts = new JsonObject();
		counts.addProperty("notStarted", notStarted);
		counts.addProperty("inProgress", inProgress);
		counts.addProperty("finished", finished);
		counts.addProperty("unknown", unknown);
		counts.addProperty("total", notStarted + inProgress + finished + unknown);
		result.add("counts", counts);
		result.add("page", page(matching, offset, limit, "quests"));
		return result;
	}

	JsonObject diaries(JsonObject arguments)
	{
		Set<String> requested = strings(arguments, "regions");
		JsonArray regions = new JsonArray();
		int completed = 0;
		int returned = 0;
		for (DiaryDefinition definition : diaryDefinitions())
		{
			JsonObject region = new JsonObject();
			region.addProperty("key", definition.key);
			region.addProperty("name", definition.name);
			JsonObject tiers = new JsonObject();
			int regionCompleted = 0;
			String[] names = {"easy", "medium", "hard", "elite"};
			for (int index = 0; index < definition.varbits.length; index++)
			{
				int value = client.getVarbitValue(definition.varbits[index]);
				JsonObject tier = new JsonObject();
				tier.addProperty("complete", value > 0);
				tier.addProperty("rewardValue", value);
				tiers.add(names[index], tier);
				if (value > 0)
				{
					regionCompleted++;
				}
			}
			completed += regionCompleted;
			region.addProperty("completedTiers", regionCompleted);
			region.addProperty("complete", regionCompleted == 4);
			region.add("tiers", tiers);
			if (requested.isEmpty() || requested.contains(definition.key))
			{
				regions.add(region);
				returned++;
			}
		}
		JsonObject result = new JsonObject();
		result.addProperty("completedTiers", completed);
		result.addProperty("totalTiers", 48);
		result.addProperty("returnedRegions", returned);
		result.add("regions", regions);
		return result;
	}

	JsonObject combatAchievements(JsonObject arguments)
	{
		Set<String> requestedTiers = strings(arguments, "tiers");
		Boolean completedFilter = bool(arguments, "completed");
		String query = string(arguments, "query");
		int offset = integer(arguments, "offset", 0);
		int limit = integer(arguments, "limit", 50);
		JsonArray tiers = new JsonArray();
		List<JsonObject> matching = new ArrayList<>();
		int allCompleted = 0;
		int allTasks = 0;
		for (Map.Entry<Integer, String> tier : CA_TIERS.entrySet())
		{
			List<CombatTask> definitions = combatTasks(tier.getKey());
			int tierCompleted = 0;
			for (CombatTask task : definitions)
			{
				boolean done = combatTaskCompleted(task.id);
				if (done)
				{
					tierCompleted++;
				}
				String wireTier = tier.getValue().toLowerCase(Locale.ROOT);
				if (!requestedTiers.isEmpty() && !requestedTiers.contains(wireTier)
					|| completedFilter != null && completedFilter != done
					|| query != null && !contains(task.name, query))
				{
					continue;
				}
				JsonObject value = new JsonObject();
				value.addProperty("id", task.id);
				value.addProperty("name", task.name);
				value.addProperty("tier", wireTier);
				value.addProperty("completed", done);
				matching.add(value);
			}
			allCompleted += tierCompleted;
			allTasks += definitions.size();
			JsonObject summary = new JsonObject();
			summary.addProperty("name", tier.getValue().toLowerCase(Locale.ROOT));
			summary.addProperty("completed", tierCompleted);
			summary.addProperty("total", definitions.size());
			tiers.add(summary);
		}
		JsonObject result = new JsonObject();
		result.addProperty("definitionsAvailable", allTasks > 0);
		result.addProperty("completed", allCompleted);
		result.addProperty("total", allTasks);
		result.add("tiers", tiers);
		result.add("page", page(matching, offset, limit, "tasks"));
		return result;
	}

	JsonObject slayer(JsonObject arguments)
	{
		Set<String> sections = strings(arguments, "sections");
		boolean all = sections.isEmpty();
		JsonObject result = new JsonObject();
		if (all || sections.contains("task"))
		{
			result.add("task", slayerTask());
		}
		if (all || sections.contains("rewards"))
		{
			JsonObject rewards = new JsonObject();
			rewards.addProperty("points", client.getVarbitValue(VarbitID.SLAYER_POINTS));
			rewards.addProperty("tasksCompleted", client.getVarbitValue(VarbitID.SLAYER_TASKS_COMPLETED));
			rewards.addProperty("wildernessTasksCompleted", client.getVarbitValue(VarbitID.SLAYER_WILDERNESS_TASKS_COMPLETED));
			rewards.add("unlocks", slayerUnlocks());
			rewards.add("extensions", slayerExtensions());
			rewards.add("autoKill", slayerAutoKill());
			result.add("rewards", rewards);
		}
		if (all || sections.contains("blocks"))
		{
			result.add("blocks", slayerBlocks());
		}
		return result;
	}

	JsonObject collectionLog()
	{
		JsonObject result = new JsonObject();
		int total = client.getVarpValue(VarPlayerID.COLLECTION_COUNT_MAX);
		boolean totalsLoaded = total > 0;
		result.addProperty("availability", totalsLoaded ? "current_summary" : "recent_only");
		result.addProperty("completeness", "summary");
		int unsynchronized = client.getVarpValue(VarPlayerID.COLLECTION_COUNT_UNSYNCED);
		result.addProperty("synchronization", !totalsLoaded || unsynchronized < 0 ? "unknown"
			: unsynchronized == 0 ? "current" : "unsynchronized");
		JsonObject totals = new JsonObject();
		totals.addProperty("obtained", client.getVarpValue(VarPlayerID.COLLECTION_COUNT));
		totals.addProperty("total", total);
		totals.add("bosses", countPair(VarPlayerID.COLLECTION_COUNT_BOSSES, VarPlayerID.COLLECTION_COUNT_BOSSES_MAX));
		totals.add("raids", countPair(VarPlayerID.COLLECTION_COUNT_RAIDS, VarPlayerID.COLLECTION_COUNT_RAIDS_MAX));
		totals.add("clues", countPair(VarPlayerID.COLLECTION_COUNT_CLUES, VarPlayerID.COLLECTION_COUNT_CLUES_MAX));
		totals.add("minigames", countPair(VarPlayerID.COLLECTION_COUNT_MINIGAMES, VarPlayerID.COLLECTION_COUNT_MINIGAMES_MAX));
		totals.add("other", countPair(VarPlayerID.COLLECTION_COUNT_OTHER, VarPlayerID.COLLECTION_COUNT_OTHER_MAX));
		result.add("totals", totals);
		JsonArray recent = new JsonArray();
		for (int index = 0; index < COLLECTION_RECENT_ITEMS.length; index++)
		{
			int itemId = client.getVarpValue(COLLECTION_RECENT_ITEMS[index]);
			if (itemId <= 0)
			{
				continue;
			}
			JsonObject item = new JsonObject();
			item.addProperty("itemId", itemId);
			ItemComposition definition = client.getItemDefinition(itemId);
			item.addProperty("name", definition == null ? null : definition.getName());
			item.addProperty("dateValueRaw", client.getVarpValue(COLLECTION_RECENT_DATES[index]));
			recent.add(item);
		}
		result.add("recentItems", recent);
		result.addProperty("detailAvailability", "unavailable");
		result.addProperty("detailReason", "RuneLite exposes no complete native collection-log entry model");
		return result;
	}

	private JsonObject slayerTask()
	{
		int taskId = client.getVarpValue(VarPlayerID.SLAYER_TARGET);
		int areaId = client.getVarpValue(VarPlayerID.SLAYER_AREA);
		int bossId = client.getVarbitValue(VarbitID.SLAYER_TARGET_BOSSID);
		int masterId = client.getVarbitValue(VarbitID.SLAYER_MASTER);
		int remaining = client.getVarpValue(VarPlayerID.SLAYER_COUNT);
		JsonObject task = new JsonObject();
		task.addProperty("active", taskId > 0 && remaining > 0);
		task.addProperty("id", taskId);
		addNullable(task, "name", slayerName(slayerTaskNames, taskId, "task"));
		task.addProperty("remaining", remaining);
		task.addProperty("initialAmount", client.getVarpValue(VarPlayerID.SLAYER_COUNT_ORIGINAL));
		task.addProperty("areaId", areaId);
		addNullable(task, "areaName", slayerName(slayerAreaNames, areaId, "area"));
		task.addProperty("masterId", masterId);
		addNullable(task, "masterName", masterId > 0 && masterId < SLAYER_MASTERS.length ? SLAYER_MASTERS[masterId] : null);
		task.addProperty("bossId", bossId);
		addNullable(task, "bossName", slayerName(slayerBossNames, bossId, "boss"));
		return task;
	}

	private JsonObject slayerUnlocks()
	{
		return namedVarbits(new String[]{
			"redDragons", "mithrilDragons", "aviansies", "tzhaar", "lizardmen", "basilisks",
			"vampyres", "warpedCreatures", "aquanites", "gryphons", "bosses", "superiorMonsters",
			"slayerHelmet", "taskStorage"
		}, new int[]{
			VarbitID.SLAYER_UNLOCK_REDDRAGONS, VarbitID.SLAYER_UNLOCK_MITHRILDRAGONS,
			VarbitID.SLAYER_UNLOCK_AVIANSIES, VarbitID.SLAYER_UNLOCK_TZHAAR,
			VarbitID.SLAYER_UNLOCK_LIZARDMEN, VarbitID.SLAYER_UNLOCK_BASILISK,
			VarbitID.SLAYER_UNLOCK_VAMPYRES, VarbitID.SLAYER_UNLOCK_WARPED_CREATURES,
			VarbitID.SLAYER_UNLOCK_AQUANITES, VarbitID.SLAYER_UNLOCK_GRYPHONS,
			VarbitID.SLAYER_UNLOCK_BOSSES, VarbitID.SLAYER_UNLOCK_SUPERIORMOBS,
			VarbitID.SLAYER_HELM_UNLOCKED, VarbitID.SLAYER_UNLOCK_STORAGE
		});
	}

	private JsonObject slayerExtensions()
	{
		return namedVarbits(new String[]{
			"aberrantSpectres", "abyssalDemons", "adamantDragons", "ankou", "aquanites",
			"araxytes", "aviansies", "basilisks", "blackDemons", "blackDragons", "bloodveld",
			"caveHorrors", "caveKraken", "darkBeasts", "dustDevils", "gargoyles", "greaterDemons",
			"mithrilDragons", "nechryael", "runeDragons", "skeletalWyverns", "suqahs", "vampyres", "wyrms"
		}, new int[]{
			VarbitID.SLAYER_LONGER_ABERRANTSPECTRES, VarbitID.SLAYER_LONGER_ABYSSALDEMONS,
			VarbitID.SLAYER_LONGER_ADAMANTDRAGONS, VarbitID.SLAYER_LONGER_ANKOU,
			VarbitID.SLAYER_LONGER_AQUANITES, VarbitID.SLAYER_LONGER_ARAXYTES,
			VarbitID.SLAYER_LONGER_AVIANSIES, VarbitID.SLAYER_LONGER_BASILISK,
			VarbitID.SLAYER_LONGER_BLACKDEMONS, VarbitID.SLAYER_LONGER_BLACKDRAGONS,
			VarbitID.SLAYER_LONGER_BLOODVELD, VarbitID.SLAYER_LONGER_CAVEHORRORS,
			VarbitID.SLAYER_LONGER_CAVEKRAKEN, VarbitID.SLAYER_LONGER_DARKBEASTS,
			VarbitID.SLAYER_LONGER_DUSTDEVILS, VarbitID.SLAYER_LONGER_GARGOYLES,
			VarbitID.SLAYER_LONGER_GREATERDEMONS, VarbitID.SLAYER_LONGER_MITHRILDRAGONS,
			VarbitID.SLAYER_LONGER_NECHRYAEL, VarbitID.SLAYER_LONGER_RUNEDRAGONS,
			VarbitID.SLAYER_LONGER_SKELETALWYVERNS, VarbitID.SLAYER_LONGER_SUQAH,
			VarbitID.SLAYER_LONGER_VAMPYRES, VarbitID.SLAYER_LONGER_WYRMS
		});
	}

	private JsonObject slayerAutoKill()
	{
		return namedVarbits(new String[]{"desertLizards", "gargoyles", "rockslugs", "zygomites"},
			new int[]{VarbitID.SLAYER_AUTOKILL_DESERTLIZARDS, VarbitID.SLAYER_AUTOKILL_GARGOYLES,
				VarbitID.SLAYER_AUTOKILL_ROCKSLUGS, VarbitID.SLAYER_AUTOKILL_ZYGOMITES});
	}

	private JsonObject slayerBlocks()
	{
		JsonObject blocks = new JsonObject();
		addBlocks(blocks, "turael", new int[]{VarbitID.SLAYER_BLOCKED_TURAEL_1, VarbitID.SLAYER_BLOCKED_TURAEL_2, VarbitID.SLAYER_BLOCKED_TURAEL_3, VarbitID.SLAYER_BLOCKED_TURAEL_4, VarbitID.SLAYER_BLOCKED_TURAEL_5, VarbitID.SLAYER_BLOCKED_TURAEL_6, VarbitID.SLAYER_BLOCKED_TURAEL_DIARY});
		addBlocks(blocks, "mazchna", new int[]{VarbitID.SLAYER_BLOCKED_MAZCHNA_1, VarbitID.SLAYER_BLOCKED_MAZCHNA_2, VarbitID.SLAYER_BLOCKED_MAZCHNA_3, VarbitID.SLAYER_BLOCKED_MAZCHNA_4, VarbitID.SLAYER_BLOCKED_MAZCHNA_5, VarbitID.SLAYER_BLOCKED_MAZCHNA_6, VarbitID.SLAYER_BLOCKED_MAZCHNA_DIARY});
		addBlocks(blocks, "vannaka", new int[]{VarbitID.SLAYER_BLOCKED_VANNAKA_1, VarbitID.SLAYER_BLOCKED_VANNAKA_2, VarbitID.SLAYER_BLOCKED_VANNAKA_3, VarbitID.SLAYER_BLOCKED_VANNAKA_4, VarbitID.SLAYER_BLOCKED_VANNAKA_5, VarbitID.SLAYER_BLOCKED_VANNAKA_6, VarbitID.SLAYER_BLOCKED_VANNAKA_DIARY});
		addBlocks(blocks, "chaeldar", new int[]{VarbitID.SLAYER_BLOCKED_CHAELDAR_1, VarbitID.SLAYER_BLOCKED_CHAELDAR_2, VarbitID.SLAYER_BLOCKED_CHAELDAR_3, VarbitID.SLAYER_BLOCKED_CHAELDAR_4, VarbitID.SLAYER_BLOCKED_CHAELDAR_5, VarbitID.SLAYER_BLOCKED_CHAELDAR_6, VarbitID.SLAYER_BLOCKED_CHAELDAR_DIARY});
		addBlocks(blocks, "konar", new int[]{VarbitID.SLAYER_BLOCKED_KONAR_1, VarbitID.SLAYER_BLOCKED_KONAR_2, VarbitID.SLAYER_BLOCKED_KONAR_3, VarbitID.SLAYER_BLOCKED_KONAR_4, VarbitID.SLAYER_BLOCKED_KONAR_5, VarbitID.SLAYER_BLOCKED_KONAR_6, VarbitID.SLAYER_BLOCKED_KONAR_DIARY});
		addBlocks(blocks, "nieve", new int[]{VarbitID.SLAYER_BLOCKED_NIEVE_1, VarbitID.SLAYER_BLOCKED_NIEVE_2, VarbitID.SLAYER_BLOCKED_NIEVE_3, VarbitID.SLAYER_BLOCKED_NIEVE_4, VarbitID.SLAYER_BLOCKED_NIEVE_5, VarbitID.SLAYER_BLOCKED_NIEVE_6, VarbitID.SLAYER_BLOCKED_NIEVE_DIARY});
		addBlocks(blocks, "duradel", new int[]{VarbitID.SLAYER_BLOCKED_DURADEL_1, VarbitID.SLAYER_BLOCKED_DURADEL_2, VarbitID.SLAYER_BLOCKED_DURADEL_3, VarbitID.SLAYER_BLOCKED_DURADEL_4, VarbitID.SLAYER_BLOCKED_DURADEL_5, VarbitID.SLAYER_BLOCKED_DURADEL_6, VarbitID.SLAYER_BLOCKED_DURADEL_DIARY});
		addBlocks(blocks, "krystilia", new int[]{VarbitID.SLAYER_BLOCKED_KRYSTILIA_1, VarbitID.SLAYER_BLOCKED_KRYSTILIA_2, VarbitID.SLAYER_BLOCKED_KRYSTILIA_3, VarbitID.SLAYER_BLOCKED_KRYSTILIA_4, VarbitID.SLAYER_BLOCKED_KRYSTILIA_5, VarbitID.SLAYER_BLOCKED_KRYSTILIA_6, VarbitID.SLAYER_BLOCKED_KRYSTILIA_DIARY});
		return blocks;
	}

	private void addBlocks(JsonObject blocks, String master, int[] varbits)
	{
		JsonArray values = new JsonArray();
		for (int index = 0; index < varbits.length; index++)
		{
			int taskId = client.getVarbitValue(varbits[index]);
			JsonObject value = new JsonObject();
			value.addProperty("slot", index == 6 ? "diary" : Integer.toString(index + 1));
			value.addProperty("taskId", taskId);
			addNullable(value, "name", slayerName(slayerTaskNames, taskId, "task"));
			values.add(value);
		}
		blocks.add(master, values);
	}

	private String slayerName(Map<Integer, String> cache, int id, String kind)
	{
		if (id <= 0)
		{
			return null;
		}
		String cached = cache.get(id);
		String missingKey = kind + ":" + id;
		if (cached != null)
		{
			return cached;
		}
		if (missingSlayerNames.contains(missingKey))
		{
			return null;
		}
		try
		{
			String value;
			if ("area".equals(kind))
			{
				value = dbName(DBTableID.SlayerArea.ID, DBTableID.SlayerArea.COL_AREA_ID,
					DBTableID.SlayerArea.COL_AREA_NAME_IN_HELPER, id);
			}
			else if ("boss".equals(kind))
			{
				List<Integer> rows = client.getDBRowsByValue(DBTableID.SlayerTaskSublist.ID,
					DBTableID.SlayerTaskSublist.COL_TASK_SUBTABLE_ID, 0, id);
				if (rows == null || rows.isEmpty())
				{
					return null;
				}
				Object[] task = client.getDBTableField(rows.get(0), DBTableID.SlayerTaskSublist.COL_TASK, 0);
				value = task == null || task.length == 0 ? null
					: dbField(((Number) task[0]).intValue(), DBTableID.SlayerTask.COL_NAME_UPPERCASE);
			}
			else
			{
				value = dbName(DBTableID.SlayerTask.ID, DBTableID.SlayerTask.COL_ID,
					DBTableID.SlayerTask.COL_NAME_UPPERCASE, id);
			}
			if (value != null)
			{
				cache.put(id, value);
			}
			else
			{
				missingSlayerNames.add(missingKey);
			}
			return value;
		}
		catch (RuntimeException ex)
		{
			missingSlayerNames.add(missingKey);
			return null;
		}
	}

	private String dbName(int table, int idColumn, int nameColumn, int id)
	{
		List<Integer> rows = client.getDBRowsByValue(table, idColumn, 0, id);
		return rows == null || rows.isEmpty() ? null : dbField(rows.get(0), nameColumn);
	}

	private String dbField(int row, int column)
	{
		Object[] values = client.getDBTableField(row, column, 0);
		return values == null || values.length == 0 || values[0] == null ? null : String.valueOf(values[0]);
	}

	private JsonObject namedVarbits(String[] names, int[] ids)
	{
		JsonObject values = new JsonObject();
		for (int index = 0; index < names.length; index++)
		{
			values.addProperty(names[index], client.getVarbitValue(ids[index]));
		}
		return values;
	}

	private List<CombatTask> combatTasks(int enumId)
	{
		List<CombatTask> cached = combatTasks.get(enumId);
		if (cached != null)
		{
			return cached;
		}
		List<CombatTask> tasks = new ArrayList<>();
		Set<Integer> taskIds = new HashSet<>();
		try
		{
			EnumComposition values = client.getEnum(enumId);
			if (values != null && values.getIntVals() != null)
			{
				for (int structId : values.getIntVals())
				{
					StructComposition struct = client.getStructComposition(structId);
					int id = struct.getIntValue(PARAM_CA_TASK_ID);
					String name = struct.getStringValue(PARAM_CA_TASK_NAME);
					if (id >= 0 && id < CA_VARPS.length * 32 && name != null
						&& !name.isEmpty() && name.length() <= 128 && taskIds.add(id))
					{
						tasks.add(new CombatTask(id, name));
					}
				}
			}
		}
		catch (RuntimeException ignored)
		{
			return tasks;
		}
		if (!tasks.isEmpty())
		{
			combatTasks.put(enumId, Collections.unmodifiableList(tasks));
		}
		return tasks;
	}

	private boolean combatTaskCompleted(int taskId)
	{
		int word = taskId / 32;
		return word >= 0 && word < CA_VARPS.length
			&& (client.getVarpValue(CA_VARPS[word]) & (1 << (taskId % 32))) != 0;
	}

	private JsonObject countPair(int obtainedVarp, int totalVarp)
	{
		JsonObject count = new JsonObject();
		count.addProperty("obtained", client.getVarpValue(obtainedVarp));
		count.addProperty("total", client.getVarpValue(totalVarp));
		return count;
	}

	private static JsonObject page(List<JsonObject> values, int offset, int limit, String field)
	{
		int from = Math.min(offset, values.size());
		int to = from + Math.min(limit, values.size() - from);
		JsonArray entries = new JsonArray();
		for (int index = from; index < to; index++)
		{
			entries.add(values.get(index));
		}
		JsonObject page = new JsonObject();
		page.addProperty("offset", offset);
		page.addProperty("limit", limit);
		page.addProperty("total", values.size());
		page.addProperty("hasMore", to < values.size());
		page.add(field, entries);
		return page;
	}

	private static Set<String> strings(JsonObject arguments, String name)
	{
		if (arguments == null || !arguments.has(name))
		{
			return Collections.emptySet();
		}
		Set<String> values = new HashSet<>();
		for (JsonElement value : arguments.getAsJsonArray(name))
		{
			values.add(value.getAsString().toLowerCase(Locale.ROOT));
		}
		return values;
	}

	private static String string(JsonObject arguments, String name)
	{
		return arguments == null || !arguments.has(name) ? null
			: arguments.get(name).getAsString().toLowerCase(Locale.ROOT);
	}

	private static int integer(JsonObject arguments, String name, int fallback)
	{
		return arguments == null || !arguments.has(name) ? fallback : arguments.get(name).getAsInt();
	}

	private static Boolean bool(JsonObject arguments, String name)
	{
		return arguments == null || !arguments.has(name) ? null : arguments.get(name).getAsBoolean();
	}

	private static boolean contains(String value, String query)
	{
		return value != null && value.toLowerCase(Locale.ROOT).contains(query);
	}

	private static void addNullable(JsonObject object, String name, String value)
	{
		if (value == null)
		{
			object.add(name, JsonNull.INSTANCE);
		}
		else
		{
			object.addProperty(name, value);
		}
	}

	private static List<DiaryDefinition> diaryDefinitions()
	{
		return Arrays.asList(
			new DiaryDefinition("ardougne", "Ardougne", VarbitID.ARDOUGNE_EASY_REWARD, VarbitID.ARDOUGNE_MEDIUM_REWARD, VarbitID.ARDOUGNE_HARD_REWARD, VarbitID.ARDOUGNE_ELITE_REWARD),
			new DiaryDefinition("desert", "Desert", VarbitID.DESERT_EASY_REWARD, VarbitID.DESERT_MEDIUM_REWARD, VarbitID.DESERT_HARD_REWARD, VarbitID.DESERT_ELITE_REWARD),
			new DiaryDefinition("falador", "Falador", VarbitID.FALADOR_EASY_REWARD, VarbitID.FALADOR_MEDIUM_REWARD, VarbitID.FALADOR_HARD_REWARD, VarbitID.FALADOR_ELITE_REWARD),
			new DiaryDefinition("fremennik", "Fremennik", VarbitID.FREMENNIK_EASY_REWARD, VarbitID.FREMENNIK_MEDIUM_REWARD, VarbitID.FREMENNIK_HARD_REWARD, VarbitID.FREMENNIK_ELITE_REWARD),
			new DiaryDefinition("kandarin", "Kandarin", VarbitID.KANDARIN_EASY_REWARD, VarbitID.KANDARIN_MEDIUM_REWARD, VarbitID.KANDARIN_HARD_REWARD, VarbitID.KANDARIN_ELITE_REWARD),
			new DiaryDefinition("karamja", "Karamja", VarbitID.ATJUN_EASY_REWARD, VarbitID.ATJUN_MED_REWARD, VarbitID.ATJUN_HARD_REWARD, VarbitID.KARAMJA_ELITE_REWARD),
			new DiaryDefinition("kourend_kebos", "Kourend & Kebos", VarbitID.KOUREND_EASY_REWARD, VarbitID.KOUREND_MEDIUM_REWARD, VarbitID.KOUREND_HARD_REWARD, VarbitID.KOUREND_ELITE_REWARD),
			new DiaryDefinition("lumbridge_draynor", "Lumbridge & Draynor", VarbitID.LUMBRIDGE_EASY_REWARD, VarbitID.LUMBRIDGE_MEDIUM_REWARD, VarbitID.LUMBRIDGE_HARD_REWARD, VarbitID.LUMBRIDGE_ELITE_REWARD),
			new DiaryDefinition("morytania", "Morytania", VarbitID.MORYTANIA_EASY_REWARD, VarbitID.MORYTANIA_MEDIUM_REWARD, VarbitID.MORYTANIA_HARD_REWARD, VarbitID.MORYTANIA_ELITE_REWARD),
			new DiaryDefinition("varrock", "Varrock", VarbitID.VARROCK_EASY_REWARD, VarbitID.VARROCK_MEDIUM_REWARD, VarbitID.VARROCK_HARD_REWARD, VarbitID.VARROCK_ELITE_REWARD),
			new DiaryDefinition("western_provinces", "Western Provinces", VarbitID.WESTERN_EASY_REWARD, VarbitID.WESTERN_MEDIUM_REWARD, VarbitID.WESTERN_HARD_REWARD, VarbitID.WESTERN_ELITE_REWARD),
			new DiaryDefinition("wilderness", "Wilderness", VarbitID.WILDERNESS_EASY_REWARD, VarbitID.WILDERNESS_MEDIUM_REWARD, VarbitID.WILDERNESS_HARD_REWARD, VarbitID.WILDERNESS_ELITE_REWARD)
		);
	}

	private static final class DiaryDefinition
	{
		private final String key;
		private final String name;
		private final int[] varbits;

		private DiaryDefinition(String key, String name, int... varbits)
		{
			this.key = key;
			this.name = name;
			this.varbits = varbits;
		}
	}

	private static final class CombatTask
	{
		private final int id;
		private final String name;

		private CombatTask(int id, String name)
		{
			this.id = id;
			this.name = name;
		}
	}
}
