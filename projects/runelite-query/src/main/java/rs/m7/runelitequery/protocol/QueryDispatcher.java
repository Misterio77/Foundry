package rs.m7.runelitequery.protocol;

import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import rs.m7.runelitequery.events.EventHistory;
import rs.m7.runelitequery.events.EventPage;
import rs.m7.runelitequery.events.EventQuery;
import rs.m7.runelitequery.events.EventRecord;
import rs.m7.runelitequery.events.EventType;
import rs.m7.runelitequery.snapshot.SnapshotProvider;
import rs.m7.runelitequery.snapshot.SnapshotType;

public class QueryDispatcher
{
	private static final int MAX_EVENT_RESPONSE_BYTES = 500 * 1024;

	private final SnapshotProvider snapshots;
	private final EventHistory events;
	private final Gson gson;

	public QueryDispatcher(SnapshotProvider snapshots, EventHistory events, Gson gson)
	{
		this.snapshots = snapshots;
		this.events = events;
		this.gson = gson.newBuilder().serializeNulls().create();
	}

	public JsonObject query(String operation, JsonObject arguments) throws Exception
	{
		if (operation == null || operation.isEmpty())
		{
			throw new IllegalArgumentException("operation must not be empty");
		}
		if (arguments == null)
		{
			arguments = new JsonObject();
		}
		String name = operation;

		switch (name)
		{
			case "context":
				rejectUnknownArguments(arguments);
				return snapshots.snapshot(SnapshotType.GAME_CONTEXT);
			case "skills":
				rejectUnknownArguments(arguments, "names");
				return skills(snapshots.snapshot(SnapshotType.SKILLS), arguments);
			case "status-effects":
				rejectUnknownArguments(arguments);
				return snapshots.snapshot(SnapshotType.STATUS_EFFECTS);
			case "carried-items":
				rejectUnknownArguments(arguments, "containers");
				return carriedItems(snapshots.snapshot(SnapshotType.CARRIED_ITEMS), arguments);
			case "events":
				rejectUnknownArguments(arguments, "generation", "afterSequence", "beforeSequence", "types", "limit");
				return eventResult(eventQuery(arguments));
			case "quests":
				validatePagedArguments(arguments, "states", "not_started", "in_progress", "finished", "unknown");
				return snapshots.snapshot(SnapshotType.QUESTS, arguments);
			case "achievement-diaries":
				rejectUnknownArguments(arguments, "regions");
				validateArray(arguments, "regions", 12, "ardougne", "desert", "falador", "fremennik",
					"kandarin", "karamja", "kourend_kebos", "lumbridge_draynor", "morytania",
					"varrock", "western_provinces", "wilderness");
				return snapshots.snapshot(SnapshotType.ACHIEVEMENT_DIARIES, arguments);
			case "combat-achievements":
				rejectUnknownArguments(arguments, "tiers", "completed", "query", "offset", "limit");
				validateArray(arguments, "tiers", 6, "easy", "medium", "hard", "elite", "master", "grandmaster");
				validateText(arguments, "query");
				validatePage(arguments);
				validateOptionalBoolean(arguments, "completed");
				return snapshots.snapshot(SnapshotType.COMBAT_ACHIEVEMENTS, arguments);
			case "slayer":
				rejectUnknownArguments(arguments, "sections");
				validateArray(arguments, "sections", 3, "task", "rewards", "blocks");
				return snapshots.snapshot(SnapshotType.SLAYER, arguments);
			case "grand-exchange":
				rejectUnknownArguments(arguments);
				return snapshots.snapshot(SnapshotType.GRAND_EXCHANGE);
			case "stored-items":
				rejectUnknownArguments(arguments, "containers", "query", "itemId", "offset", "limit");
				validateArray(arguments, "containers", 4, "bank", "seed_vault", "looting_bag", "rune_pouch",
					"seed_box", "tackle_box", "forestry_kit", "huntsmans_kit");
				validateText(arguments, "query");
				validatePage(arguments);
				validatePositive(arguments, "itemId");
				return snapshots.snapshot(SnapshotType.STORED_ITEMS, arguments);
			case "account-wealth":
				rejectUnknownArguments(arguments);
				return snapshots.snapshot(SnapshotType.ACCOUNT_WEALTH);
			case "collection-log":
				rejectUnknownArguments(arguments);
				return snapshots.snapshot(SnapshotType.COLLECTION_LOG);
			case "poh":
				rejectUnknownArguments(arguments);
				return snapshots.snapshot(SnapshotType.POH_STATE);
			case "item-prices":
				rejectUnknownArguments(arguments, "itemIds");
				validateItemIds(arguments);
				return snapshots.snapshot(SnapshotType.ITEM_PRICES, arguments);
			default:
				throw new IllegalArgumentException("Unknown operation: " + name);
		}
	}

	private JsonObject skills(JsonObject snapshot, JsonObject arguments)
	{
		Set<String> names = new HashSet<>();
		if (arguments.has("names"))
		{
			if (!arguments.get("names").isJsonArray())
			{
				throw new IllegalArgumentException("names must be an array of strings");
			}
			for (JsonElement name : arguments.getAsJsonArray("names"))
			{
				if (!name.isJsonPrimitive() || !name.getAsJsonPrimitive().isString())
				{
					throw new IllegalArgumentException("names must be an array of strings");
				}
				names.add(name.getAsString().toLowerCase(Locale.ROOT));
			}
		}

		JsonArray filtered = new JsonArray();
		for (JsonElement skill : snapshot.getAsJsonArray("skills"))
		{
			String name = skill.getAsJsonObject().get("name").getAsString();
			if (names.isEmpty() || names.contains(name.toLowerCase(Locale.ROOT)))
			{
				filtered.add(skill.deepCopy());
			}
		}

		JsonObject result = new JsonObject();
		result.add("state", snapshot.get("state").deepCopy());
		result.add("sample", snapshot.get("sample").deepCopy());
		result.add("skills", filtered);
		return result;
	}

	private JsonObject carriedItems(JsonObject snapshot, JsonObject arguments)
	{
		boolean filtered = arguments.has("containers");
		Set<String> requested = stringArray(arguments, "containers");
		if (filtered && requested.isEmpty())
		{
			throw new IllegalArgumentException("containers must not be empty");
		}
		JsonObject available = snapshot.getAsJsonObject("containers");
		JsonObject selected = new JsonObject();
		for (String name : new String[]{"inventory", "equipment"})
		{
			if (!filtered || requested.contains(name))
			{
				selected.add(name, available.get(name).deepCopy());
			}
		}
		if (selected.size() != (filtered ? requested.size() : 2))
		{
			throw new IllegalArgumentException("containers must contain only inventory or equipment");
		}

		JsonObject result = new JsonObject();
		result.add("state", snapshot.get("state").deepCopy());
		result.add("sample", snapshot.get("sample").deepCopy());
		result.add("containers", selected);
		return result;
	}

	private static Set<String> stringArray(JsonObject arguments, String name)
	{
		Set<String> values = new HashSet<>();
		if (!arguments.has(name))
		{
			return values;
		}
		if (!arguments.get(name).isJsonArray())
		{
			throw new IllegalArgumentException(name + " must be an array of strings");
		}
		for (JsonElement value : arguments.getAsJsonArray(name))
		{
			if (!value.isJsonPrimitive() || !value.getAsJsonPrimitive().isString())
			{
				throw new IllegalArgumentException(name + " must be an array of strings");
			}
			if (!values.add(value.getAsString()))
			{
				throw new IllegalArgumentException(name + " must not contain duplicates");
			}
		}
		return values;
	}

	private static void validateItemIds(JsonObject arguments)
	{
		if (!arguments.has("itemIds") || !arguments.get("itemIds").isJsonArray())
		{
			throw new IllegalArgumentException("itemIds must be an array");
		}
		JsonArray ids = arguments.getAsJsonArray("itemIds");
		if (ids.size() < 1 || ids.size() > 8)
		{
			throw new IllegalArgumentException("itemIds must contain between 1 and 8 IDs");
		}
		Set<Integer> unique = new HashSet<>();
		for (JsonElement element : ids)
		{
			if (!element.isJsonPrimitive() || !element.getAsJsonPrimitive().isNumber())
			{
				throw new IllegalArgumentException("itemIds must contain positive integers");
			}
			try
			{
				int id = new BigDecimal(element.getAsString()).toBigIntegerExact().intValueExact();
				if (id <= 0 || !unique.add(id))
				{
					throw new IllegalArgumentException("itemIds must contain unique positive integers");
				}
			}
			catch (ArithmeticException | NumberFormatException ex)
			{
				throw new IllegalArgumentException("itemIds must contain positive 32-bit integers");
			}
		}
	}

	private static void validatePagedArguments(JsonObject arguments, String selector, String... allowed)
	{
		rejectUnknownArguments(arguments, selector, "query", "offset", "limit");
		validateArray(arguments, selector, allowed.length, allowed);
		validateText(arguments, "query");
		validatePage(arguments);
	}

	private static void validateArray(JsonObject arguments, String name, int maximum, String... allowed)
	{
		if (!arguments.has(name))
		{
			return;
		}
		Set<String> values = stringArray(arguments, name);
		if (values.isEmpty() || values.size() > maximum)
		{
			throw new IllegalArgumentException(name + " must contain between 1 and " + maximum + " values");
		}
		Set<String> accepted = new HashSet<>();
		java.util.Collections.addAll(accepted, allowed);
		if (!accepted.containsAll(values))
		{
			throw new IllegalArgumentException(name + " contains an unknown value");
		}
	}

	private static void validatePage(JsonObject arguments)
	{
		if (arguments.has("offset") && requiredInt(arguments, "offset") < 0)
		{
			throw new IllegalArgumentException("offset must be nonnegative");
		}
		if (arguments.has("limit"))
		{
			int limit = requiredInt(arguments, "limit");
			if (limit < 1 || limit > 100)
			{
				throw new IllegalArgumentException("limit must be between 1 and 100");
			}
		}
	}

	private static void validateText(JsonObject arguments, String name)
	{
		String value = optionalString(arguments, name);
		if (value != null && (value.isEmpty() || value.length() > 128))
		{
			throw new IllegalArgumentException(name + " must contain between 1 and 128 characters");
		}
	}

	private static void validateOptionalBoolean(JsonObject arguments, String name)
	{
		if (arguments.has(name)
			&& (!arguments.get(name).isJsonPrimitive() || !arguments.getAsJsonPrimitive(name).isBoolean()))
		{
			throw new IllegalArgumentException(name + " must be a boolean");
		}
	}

	private static void validatePositive(JsonObject arguments, String name)
	{
		if (arguments.has(name) && optionalLong(arguments, name) <= 0)
		{
			throw new IllegalArgumentException(name + " must be positive");
		}
	}

	private JsonObject eventResult(EventQuery query)
	{
		EventPage page = events.query(query);
		List<EventRecord> records = new ArrayList<>(page.getEvents());
		boolean hasOlder = page.hasOlder();
		boolean hasNewer = page.hasNewer();
		JsonObject structured = eventPage(page, records, hasOlder, hasNewer, false);
		if (gson.toJson(structured).getBytes(StandardCharsets.UTF_8).length <= MAX_EVENT_RESPONSE_BYTES)
		{
			return structured;
		}

		int low = 1;
		int high = records.size();
		int fitting = 0;
		while (low <= high)
		{
			int middle = (low + high) >>> 1;
			List<EventRecord> candidate = eventSlice(records, page.getDirection(), middle);
			boolean candidateOlder = hasOlder || page.getDirection() != EventQuery.Direction.FORWARD
				&& candidate.size() < records.size();
			boolean candidateNewer = hasNewer || page.getDirection() == EventQuery.Direction.FORWARD
				&& candidate.size() < records.size();
			JsonObject value = eventPage(page, candidate, candidateOlder, candidateNewer, true);
			if (gson.toJson(value).getBytes(StandardCharsets.UTF_8).length <= MAX_EVENT_RESPONSE_BYTES)
			{
				fitting = middle;
				low = middle + 1;
			}
			else
			{
				high = middle - 1;
			}
		}
		if (fitting == 0)
		{
			throw new IllegalArgumentException("A retained event exceeds the response size limit");
		}
		records = eventSlice(records, page.getDirection(), fitting);
		hasOlder = hasOlder || page.getDirection() != EventQuery.Direction.FORWARD;
		hasNewer = hasNewer || page.getDirection() == EventQuery.Direction.FORWARD;
		return eventPage(page, records, hasOlder, hasNewer, true);
	}

	private static List<EventRecord> eventSlice(List<EventRecord> records,
		EventQuery.Direction direction, int count)
	{
		if (direction == EventQuery.Direction.FORWARD)
		{
			return new ArrayList<>(records.subList(0, count));
		}
		return new ArrayList<>(records.subList(records.size() - count, records.size()));
	}

	private static JsonObject eventPage(EventPage page, List<EventRecord> records,
		boolean hasOlder, boolean hasNewer, boolean sizeLimited)
	{
		JsonObject result = new JsonObject();
		result.addProperty("state", page.getMetadata().getState());
		JsonObject sample = new JsonObject();
		sample.addProperty("gameState", page.getMetadata().getGameState());
		sample.addProperty("tick", page.getMetadata().getTick());
		result.add("sample", sample);

		JsonObject history = new JsonObject();
		history.addProperty("generation", page.getGeneration());
		addNullable(history, "oldestSequence", page.getOldestSequence());
		addNullable(history, "newestSequence", page.getNewestSequence());
		addNullable(history, "pageFirstSequence", records.isEmpty() ? null : records.get(0).getSequence());
		addNullable(history, "pageLastSequence", records.isEmpty() ? null : records.get(records.size() - 1).getSequence());
		history.addProperty("pollAfterSequence", page.getPollAfterSequence());
		history.addProperty("hasOlder", hasOlder);
		history.addProperty("hasNewer", hasNewer);
		history.addProperty("gap", page.hasGap());
		history.addProperty("sizeLimited", sizeLimited);
		history.addProperty("droppedEvents", page.getDroppedEvents());
		JsonArray values = new JsonArray();
		for (EventRecord record : records)
		{
			values.add(record.toJson());
		}
		history.add("events", values);
		result.add("history", history);
		return result;
	}

	private static void addNullable(JsonObject object, String name, Long value)
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

	private static EventQuery eventQuery(JsonObject arguments)
	{
		String generation = optionalString(arguments, "generation");
		Long after = optionalLong(arguments, "afterSequence");
		Long before = optionalLong(arguments, "beforeSequence");
		int limit = arguments.has("limit") ? requiredInt(arguments, "limit") : 50;
		if (limit < 1 || limit > 100)
		{
			throw new IllegalArgumentException("limit must be between 1 and 100");
		}

		Set<EventType> types = EnumSet.noneOf(EventType.class);
		if (arguments.has("types"))
		{
			Set<String> names = stringArray(arguments, "types");
			if (names.isEmpty() || names.size() > EventType.values().length)
			{
				throw new IllegalArgumentException("types must contain between 1 and 6 unique event types");
			}
			for (String name : names)
			{
				types.add(EventType.fromWireName(name));
			}
		}
		return new EventQuery(generation, after, before, types, limit);
	}

	private static String optionalString(JsonObject object, String name)
	{
		if (!object.has(name))
		{
			return null;
		}
		if (!object.get(name).isJsonPrimitive() || !object.getAsJsonPrimitive(name).isString())
		{
			throw new IllegalArgumentException(name + " must be a string");
		}
		return object.get(name).getAsString();
	}

	private static Long optionalLong(JsonObject object, String name)
	{
		if (!object.has(name))
		{
			return null;
		}
		if (!object.get(name).isJsonPrimitive() || !object.getAsJsonPrimitive(name).isNumber())
		{
			throw new IllegalArgumentException(name + " must be an integer");
		}
		try
		{
			return new BigDecimal(object.get(name).getAsString()).toBigIntegerExact().longValueExact();
		}
		catch (ArithmeticException | NumberFormatException ex)
		{
			throw new IllegalArgumentException(name + " must be an integer within signed 64-bit range");
		}
	}

	private static int requiredInt(JsonObject object, String name)
	{
		Long value = optionalLong(object, name);
		if (value == null || value < Integer.MIN_VALUE || value > Integer.MAX_VALUE)
		{
			throw new IllegalArgumentException(name + " must be an integer");
		}
		return value.intValue();
	}

	private static void rejectUnknownArguments(JsonObject arguments, String... allowed)
	{
		Set<String> names = new HashSet<>();
		for (String name : allowed)
		{
			names.add(name);
		}
		for (String name : arguments.keySet())
		{
			if (!names.contains(name))
			{
				throw new IllegalArgumentException("Unknown argument: " + name);
			}
		}
	}


}
