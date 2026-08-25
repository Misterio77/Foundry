package rs.m7.runelitequery.protocol;

import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import org.junit.Test;
import rs.m7.runelitequery.events.EventHistory;
import rs.m7.runelitequery.events.EventMetadata;
import rs.m7.runelitequery.events.EventPayloads.ContainerChange;
import rs.m7.runelitequery.events.EventPayloads.GameStateChange;
import rs.m7.runelitequery.events.EventPayloads.ItemChange;
import rs.m7.runelitequery.events.EventPayloads.ItemValue;
import rs.m7.runelitequery.events.EventType;
import rs.m7.runelitequery.events.PendingEvent;
import rs.m7.runelitequery.snapshot.SnapshotProvider;
import rs.m7.runelitequery.snapshot.SnapshotType;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

public class QueryDispatcherTest
{
	private final EventHistory eventHistory = new EventHistory();
	private final RecordingProvider snapshots = new RecordingProvider();
	private final QueryDispatcher dispatcher = new QueryDispatcher(snapshots, eventHistory, new Gson());

	@Test
	public void returnsMockedRuneLiteShapesWithoutProtocolEnvelopes() throws Exception
	{
		for (Operation operation : Operation.values())
		{
			JsonObject arguments = operation.arguments();
			JsonObject result = dispatcher.query(operation.name, arguments);
			assertEquals("active", result.get("state").getAsString());
			assertEquals("LOGGED_IN", result.getAsJsonObject("sample").get("gameState").getAsString());
			assertFalse(result.has("jsonrpc"));
			assertFalse(result.has("structuredContent"));
		}
	}

	@Test
	public void preservesLoadingAndLoggedOutResponseShapes() throws Exception
	{
		for (String[] state : new String[][]{{"loading", "HOPPING"}, {"logged_out", "LOGIN_SCREEN"}})
		{
			QueryDispatcher stateDispatcher = new QueryDispatcher(
				type -> FixtureSnapshots.unavailableContext(state[0], state[1]), new EventHistory(), new Gson());
			JsonObject result = stateDispatcher.query("context", new JsonObject());
			assertEquals(state[0], result.get("state").getAsString());
			assertEquals(state[1], result.getAsJsonObject("sample").get("gameState").getAsString());
			assertTrue(result.get("player").isJsonNull());
		}
	}

	@Test
	public void filtersSkillsAndCarriedContainers() throws Exception
	{
		JsonObject skillArguments = new JsonObject();
		JsonArray names = new JsonArray();
		names.add("agility");
		skillArguments.add("names", names);
		JsonObject skills = dispatcher.query("skills", skillArguments);
		assertEquals(1, skills.getAsJsonArray("skills").size());
		assertEquals("Agility", skills.getAsJsonArray("skills").get(0).getAsJsonObject().get("name").getAsString());

		JsonObject itemArguments = new JsonObject();
		JsonArray containers = new JsonArray();
		containers.add("equipment");
		itemArguments.add("containers", containers);
		JsonObject items = dispatcher.query("carried-items", itemArguments);
		assertFalse(items.getAsJsonObject("containers").has("inventory"));
		assertTrue(items.getAsJsonObject("containers").has("equipment"));
	}

	@Test
	public void passesTypedFiltersToMockedRuneLiteReaders() throws Exception
	{
		JsonObject arguments = new JsonObject();
		JsonArray states = new JsonArray();
		states.add("in_progress");
		arguments.add("states", states);
		arguments.addProperty("query", "fairy");
		arguments.addProperty("offset", 2);
		arguments.addProperty("limit", 10);

		dispatcher.query("quests", arguments);
		assertEquals(SnapshotType.QUESTS, snapshots.lastType);
		assertEquals(arguments, snapshots.lastArguments);
	}

	@Test
	public void queriesGenerationAwareEventHistory() throws Exception
	{
		eventHistory.appendBatch(new EventMetadata("active", "LOGGED_IN", 123),
			Collections.singletonList(new PendingEvent(EventType.GAME_STATE_CHANGED, 123,
				new GameStateChange("LOADING", "LOGGED_IN", "active"))));
		JsonObject initial = dispatcher.query("events", new JsonObject());
		JsonObject history = initial.getAsJsonObject("history");
		assertEquals(1, history.getAsJsonArray("events").size());

		JsonObject cursor = new JsonObject();
		cursor.addProperty("generation", history.get("generation").getAsString());
		cursor.addProperty("afterSequence", 1);
		JsonObject polled = dispatcher.query("events", cursor);
		assertEquals(0, polled.getAsJsonObject("history").getAsJsonArray("events").size());
	}

	@Test
	public void boundsLargeEventResponses() throws Exception
	{
		String name = String.join("", Collections.nCopies(64, "界"));
		List<ItemChange> changes = new ArrayList<>();
		for (int slot = 0; slot < 12; slot++)
		{
			changes.add(new ItemChange(slot, null,
				new ItemValue(100 + slot, name, 1), new ItemValue(200 + slot, name, 1)));
		}
		for (int tick = 1; tick <= 100; tick++)
		{
			eventHistory.appendBatch(new EventMetadata("active", "LOGGED_IN", tick),
				Collections.singletonList(new PendingEvent(EventType.INVENTORY_CHANGED, tick,
					new ContainerChange(changes, false, 28))));
		}
		JsonObject arguments = new JsonObject();
		arguments.addProperty("limit", 100);
		JsonObject history = dispatcher.query("events", arguments).getAsJsonObject("history");
		assertTrue(history.get("sizeLimited").getAsBoolean());
		assertTrue(history.getAsJsonArray("events").size() > 0);
		assertTrue(history.getAsJsonArray("events").size() < 100);
		assertEquals(100, history.get("pageLastSequence").getAsLong());
	}

	@Test
	public void rejectsInvalidArgumentsAndRemovedOperations() throws Exception
	{
		assertInvalid("context", object("fresh", true));
		assertInvalid("carried-items", arrayObject("containers"));
		assertInvalid("events", object("limit", 101));
		assertInvalid("quests", object("query", ""));
		assertInvalid("combat-achievements", object("completed", "yes"));
		assertInvalid("stored-items", object("itemId", 0));
		assertInvalid("item-prices", new JsonObject());
		assertInvalid("get_game_context", new JsonObject());
		assertInvalid("search_osrs_wiki", object("query", "Barrows"));
	}

	private void assertInvalid(String operation, JsonObject arguments) throws Exception
	{
		try
		{
			dispatcher.query(operation, arguments);
			fail("Expected invalid operation or arguments: " + operation);
		}
		catch (IllegalArgumentException expected)
		{
			// Expected.
		}
	}

	private static JsonObject object(String name, String value)
	{
		JsonObject object = new JsonObject();
		object.addProperty(name, value);
		return object;
	}

	private static JsonObject object(String name, int value)
	{
		JsonObject object = new JsonObject();
		object.addProperty(name, value);
		return object;
	}

	private static JsonObject object(String name, boolean value)
	{
		JsonObject object = new JsonObject();
		object.addProperty(name, value);
		return object;
	}

	private static JsonObject arrayObject(String name)
	{
		JsonObject object = new JsonObject();
		object.add(name, new JsonArray());
		return object;
	}

	private enum Operation
	{
		CONTEXT("context"),
		SKILLS("skills"),
		STATUS_EFFECTS("status-effects"),
		CARRIED_ITEMS("carried-items"),
		QUESTS("quests"),
		ACHIEVEMENT_DIARIES("achievement-diaries"),
		COMBAT_ACHIEVEMENTS("combat-achievements"),
		SLAYER("slayer"),
		GRAND_EXCHANGE("grand-exchange"),
		STORED_ITEMS("stored-items"),
		ACCOUNT_WEALTH("account-wealth"),
		COLLECTION_LOG("collection-log"),
		POH("poh"),
		ITEM_PRICES("item-prices");

		private final String name;

		Operation(String name)
		{
			this.name = name;
		}

		private JsonObject arguments()
		{
			JsonObject arguments = new JsonObject();
			if (this == ITEM_PRICES)
			{
				JsonArray ids = new JsonArray();
				ids.add(995);
				arguments.add("itemIds", ids);
			}
			return arguments;
		}
	}

	private static final class RecordingProvider implements SnapshotProvider
	{
		private SnapshotType lastType;
		private JsonObject lastArguments;

		@Override
		public JsonObject snapshot(SnapshotType type)
		{
			lastType = type;
			lastArguments = new JsonObject();
			return FixtureSnapshots.active(type);
		}

		@Override
		public JsonObject snapshot(SnapshotType type, JsonObject arguments)
		{
			lastType = type;
			lastArguments = arguments.deepCopy();
			return FixtureSnapshots.active(type);
		}
	}
}
