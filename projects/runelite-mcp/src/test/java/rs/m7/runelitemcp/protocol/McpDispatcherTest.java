package rs.m7.runelitemcp.protocol;

import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import org.junit.Test;
import rs.m7.runelitemcp.events.EventHistory;
import rs.m7.runelitemcp.events.EventMetadata;
import rs.m7.runelitemcp.events.EventPayloads.ContainerChange;
import rs.m7.runelitemcp.events.EventPayloads.GameStateChange;
import rs.m7.runelitemcp.events.EventPayloads.ItemChange;
import rs.m7.runelitemcp.events.EventPayloads.ItemValue;
import rs.m7.runelitemcp.events.EventType;
import rs.m7.runelitemcp.events.PendingEvent;
import rs.m7.runelitemcp.knowledge.WikiProvider;
import rs.m7.runelitemcp.snapshot.SnapshotType;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

public class McpDispatcherTest
{
	private final EventHistory eventHistory = new EventHistory();
	private final McpDispatcher dispatcher = new McpDispatcher(McpDispatcherTest::activeSnapshot, eventHistory, new Gson());

	@Test
	public void initializesWithReadCapabilities()
	{
		JsonObject response = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{},\"clientInfo\":{\"name\":\"test\",\"version\":\"1\"}}}"));
		JsonObject result = response.getAsJsonObject("result");
		assertEquals("2025-11-25", result.get("protocolVersion").getAsString());
		assertTrue(result.getAsJsonObject("capabilities").has("tools"));
		assertFalse(result.getAsJsonObject("capabilities").has("resources"));
		assertTrue(result.getAsJsonObject("capabilities").has("prompts"));
	}

	@Test
	public void rejectsLegacyProtocolVersionsRatherThanCarryingCompatibilityPaths()
	{
		JsonObject response = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\",\"capabilities\":{},\"clientInfo\":{\"name\":\"test\",\"version\":\"1\"}}}"));
		assertEquals(-32602, response.getAsJsonObject("error").get("code").getAsInt());
	}

	@Test
	public void validatesRequiredInitializationMetadata()
	{
		JsonObject response = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\"}}"));
		assertEquals(-32602, response.getAsJsonObject("error").get("code").getAsInt());
	}

	@Test
	public void listsReplacementToolsAndReturnsStructuredGameContext()
	{
		JsonObject listed = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/list\"}"));
		JsonArray tools = listed.getAsJsonObject("result").getAsJsonArray("tools");
		assertEquals(14, tools.size());
		assertEquals("get_game_context", tools.get(0).getAsJsonObject().get("name").getAsString());
		assertEquals("get_skills", tools.get(1).getAsJsonObject().get("name").getAsString());
		assertEquals("get_status_effects", tools.get(2).getAsJsonObject().get("name").getAsString());
		assertEquals("get_carried_items", tools.get(3).getAsJsonObject().get("name").getAsString());
		assertEquals("get_events", tools.get(4).getAsJsonObject().get("name").getAsString());
		assertEquals("get_quests", tools.get(5).getAsJsonObject().get("name").getAsString());
		assertEquals("get_stored_items", tools.get(10).getAsJsonObject().get("name").getAsString());
		assertEquals("get_collection_log", tools.get(12).getAsJsonObject().get("name").getAsString());
		assertEquals("get_item_prices", tools.get(13).getAsJsonObject().get("name").getAsString());

		JsonObject result = structured(dispatch("{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"get_game_context\",\"arguments\":{}}}"));
		assertEquals("active", result.get("state").getAsString());
		assertEquals("LOGGED_IN", result.getAsJsonObject("sample").get("gameState").getAsString());
		assertEquals(123, result.getAsJsonObject("sample").get("tick").getAsInt());
		assertEquals("Gabs", result.getAsJsonObject("player").get("name").getAsString());
		assertFalse(result.has("skills"));
	}

	@Test
	public void reportsLoadingAndLoggedOutAsSuccessfulStableStates()
	{
		assertUnavailableContext(unavailableContext("loading", "HOPPING"), "loading", "HOPPING");
		assertUnavailableContext(unavailableContext("logged_out", "LOGIN_SCREEN"), "logged_out", "LOGIN_SCREEN");
	}

	@Test
	public void filtersSkillsWithTheSharedStateEnvelope()
	{
		JsonObject result = structured(dispatch("{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"get_skills\",\"arguments\":{\"names\":[\"Agility\"]}}}"));
		JsonArray skills = result.getAsJsonArray("skills");
		assertEquals("active", result.get("state").getAsString());
		assertEquals(123, result.getAsJsonObject("sample").get("tick").getAsInt());
		assertEquals(1, skills.size());
		assertEquals("Agility", skills.get(0).getAsJsonObject().get("name").getAsString());
		assertEquals(72, skills.get(0).getAsJsonObject().get("baseLevel").getAsInt());
	}

	@Test
	public void returnsStatusEffects()
	{
		JsonObject result = structured(dispatch("{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"get_status_effects\",\"arguments\":{}}}"));
		JsonObject effects = result.getAsJsonObject("effects");
		assertEquals("current", effects.get("availability").getAsString());
		assertEquals("Strength", effects.getAsJsonArray("boosts").get(0).getAsJsonObject().get("skill").getAsString());
		assertEquals("protect_from_melee", effects.getAsJsonArray("activePrayers").get(0).getAsString());
		assertEquals("none", effects.getAsJsonObject("poison").get("state").getAsString());
	}

	@Test
	public void filtersCarriedItemContainers()
	{
		JsonObject result = structured(dispatch("{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"get_carried_items\",\"arguments\":{\"containers\":[\"equipment\"]}}}"));
		JsonObject containers = result.getAsJsonObject("containers");
		assertFalse(containers.has("inventory"));
		assertEquals("current", containers.getAsJsonObject("equipment").get("availability").getAsString());
		assertEquals("weapon", containers.getAsJsonObject("equipment").getAsJsonArray("items")
			.get(0).getAsJsonObject().get("slotName").getAsString());
	}

	@Test
	public void queriesEventHistoryWithGenerationCursors()
	{
		eventHistory.appendBatch(new EventMetadata("active", "LOGGED_IN", 123),
			Collections.singletonList(new PendingEvent(EventType.GAME_STATE_CHANGED, 123,
				new GameStateChange("LOADING", "LOGGED_IN", "active"))));
		JsonObject initial = structured(dispatch("{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":\"get_events\",\"arguments\":{}}}"));
		JsonObject history = initial.getAsJsonObject("history");
		assertEquals(1, history.getAsJsonArray("events").size());
		assertEquals("game_state_changed", history.getAsJsonArray("events").get(0)
			.getAsJsonObject().get("type").getAsString());

		String generation = history.get("generation").getAsString();
		JsonObject polled = structured(dispatch("{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"tools/call\",\"params\":{\"name\":\"get_events\",\"arguments\":{\"generation\":\"" + generation + "\",\"afterSequence\":1}}}"));
		assertEquals(0, polled.getAsJsonObject("history").getAsJsonArray("events").size());
	}

	@Test
	public void trimsLargeEventResultsWithoutBreakingLatestPageCursors()
	{
		String name = String.join("", Collections.nCopies(64, "界"));
		List<ItemChange> changes = new ArrayList<>();
		for (int slot = 0; slot < 6; slot++)
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

		JsonObject history = structured(dispatch("{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"tools/call\",\"params\":{\"name\":\"get_events\",\"arguments\":{\"limit\":100}}}"))
			.getAsJsonObject("history");
		assertTrue(history.get("sizeLimited").getAsBoolean());
		assertTrue(history.getAsJsonArray("events").size() > 0);
		assertTrue(history.getAsJsonArray("events").size() < 100);
		assertTrue(history.get("hasOlder").getAsBoolean());
		assertEquals(100, history.get("pageLastSequence").getAsLong());
		assertEquals(100, history.get("pollAfterSequence").getAsLong());
	}

	@Test
	public void advertisesWikiToolsOnlyWhenOutboundAccessIsEnabled()
	{
		JsonObject disabled = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":19,\"method\":\"tools/call\",\"params\":{\"name\":\"search_osrs_wiki\",\"arguments\":{\"query\":\"Barrows\"}}}"));
		assertEquals(-32602, disabled.getAsJsonObject("error").get("code").getAsInt());

		WikiProvider wiki = new WikiProvider()
		{
			@Override public boolean isEnabled() { return true; }
			@Override public JsonObject search(String query, int limit)
			{
				JsonObject value = new JsonObject();
				value.addProperty("query", query);
				value.addProperty("limit", limit);
				return value;
			}
			@Override public JsonObject page(String title, int maxCharacters) { return new JsonObject(); }
		};
		McpDispatcher enabled = new McpDispatcher(McpDispatcherTest::activeSnapshot,
			new EventHistory(), wiki, new Gson());
		JsonArray tools = response(enabled.dispatch("{\"jsonrpc\":\"2.0\",\"id\":20,\"method\":\"tools/list\"}"))
			.getAsJsonObject("result").getAsJsonArray("tools");
		assertEquals(16, tools.size());
		JsonObject result = structured(enabled.dispatch("{\"jsonrpc\":\"2.0\",\"id\":21,\"method\":\"tools/call\",\"params\":{\"name\":\"search_osrs_wiki\",\"arguments\":{\"query\":\"Barrows\",\"limit\":3}}}"));
		assertEquals("Barrows", result.get("query").getAsString());
		assertEquals(3, result.get("limit").getAsInt());
	}

	@Test
	public void removesProvisionalInterfacesRatherThanAliasingThem()
	{
		for (String name : new String[]{"client_state", "skills"})
		{
			JsonObject oldTool = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":\"" + name + "\",\"arguments\":{}}}"));
			assertTrue(oldTool.getAsJsonObject("result").get("isError").getAsBoolean());
		}
	}

	@Test
	public void validatesToolArgumentsAgainstAdvertisedSchemas()
	{
		assertInvalidArguments("get_game_context", "[]");
		assertInvalidArguments("get_game_context", "{\"fresh\":true}");
		assertInvalidArguments("get_skills", "{\"limit\":1}");
		assertInvalidArguments("get_carried_items", "{\"containers\":[]}");
		assertInvalidArguments("get_carried_items", "{\"containers\":[\"bank\"]}");
		assertInvalidArguments("get_carried_items", "{\"containers\":[\"inventory\",\"inventory\"]}");
		assertInvalidArguments("get_events", "{\"afterSequence\":0}");
		assertInvalidArguments("get_events", "{\"generation\":\"stale\",\"afterSequence\":0}");
		assertInvalidArguments("get_events", "{\"types\":[]}");
		assertInvalidArguments("get_events", "{\"limit\":101}");
		assertInvalidArguments("get_quests", "{\"states\":[]}");
		assertInvalidArguments("get_quests", "{\"query\":\"\"}");
		assertInvalidArguments("get_quests", "{\"limit\":101}");
		assertInvalidArguments("get_achievement_diaries", "{\"regions\":[\"gielinor\"]}");
		assertInvalidArguments("get_combat_achievements", "{\"completed\":\"yes\"}");
		assertInvalidArguments("get_slayer", "{\"sections\":[\"social\"]}");
		assertInvalidArguments("get_stored_items", "{\"itemId\":0}");
		assertInvalidArguments("get_stored_items", "{\"containers\":[\"bank\",\"seed_vault\",\"looting_bag\",\"rune_pouch\",\"seed_box\"]}");
		assertInvalidArguments("get_item_prices", "{}");
		assertInvalidArguments("get_item_prices", "{\"itemIds\":[995,995]}");
		assertInvalidArguments("get_item_prices", "{\"itemIds\":[1.5]}");
	}

	@Test
	public void rejectsInvalidJsonRpcIds()
	{
		for (String id : new String[]{"true", "[]", "{}", "1.5", "9223372036854775808"})
		{
			JsonObject response = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":" + id + ",\"method\":\"ping\"}"));
			assertTrue(response.get("id").isJsonNull());
			assertEquals(-32600, response.getAsJsonObject("error").get("code").getAsInt());
		}
	}

	@Test
	public void handlesNotificationsAndProtocolErrors()
	{
		DispatchResult notification = dispatch("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}");
		assertEquals(202, notification.getStatus());
		assertNull(notification.getBody());

		DispatchResult unknownNotification = dispatch("{\"jsonrpc\":\"2.0\",\"method\":\"anything\"}");
		assertEquals(202, unknownNotification.getStatus());
		assertNull(unknownNotification.getBody());

		JsonObject malformed = response(dispatch("not json"));
		assertEquals(-32700, malformed.getAsJsonObject("error").get("code").getAsInt());

		JsonObject unknown = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"unknown\"}"));
		assertEquals(-32601, unknown.getAsJsonObject("error").get("code").getAsInt());
	}

	@Test
	public void doesNotAdvertiseOrServeResources()
	{
		JsonObject response = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"resources/read\",\"params\":{\"uri\":\"runelite://game/context\"}}"));
		assertEquals(-32601, response.getAsJsonObject("error").get("code").getAsInt());
	}

	private void assertInvalidArguments(String name, String arguments)
	{
		JsonObject response = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":13,\"method\":\"tools/call\",\"params\":{\"name\":\"" + name + "\",\"arguments\":" + arguments + "}}"));
		assertEquals(-32602, response.getAsJsonObject("error").get("code").getAsInt());
	}

	private void assertUnavailableContext(JsonObject snapshot, String state, String gameState)
	{
		McpDispatcher stateDispatcher = new McpDispatcher(type -> snapshot, new EventHistory(), new Gson());
		JsonObject result = structured(stateDispatcher.dispatch("{\"jsonrpc\":\"2.0\",\"id\":14,\"method\":\"tools/call\",\"params\":{\"name\":\"get_game_context\",\"arguments\":{}}}"));
		assertEquals(state, result.get("state").getAsString());
		assertEquals(gameState, result.getAsJsonObject("sample").get("gameState").getAsString());
		assertTrue(result.get("player").isJsonNull());
		assertTrue(result.getAsJsonObject("session").get("world").isJsonNull());
		assertTrue(result.getAsJsonObject("session").get("accountType").isJsonNull());
	}

	private DispatchResult dispatch(String request)
	{
		return dispatcher.dispatch(request);
	}

	private static JsonObject structured(DispatchResult result)
	{
		return response(result).getAsJsonObject("result").getAsJsonObject("structuredContent");
	}

	private static JsonObject response(DispatchResult result)
	{
		assertEquals(200, result.getStatus());
		return new JsonParser().parse(result.getBody()).getAsJsonObject();
	}

	private static JsonObject activeSnapshot(SnapshotType type)
	{
		JsonObject snapshot = baseSnapshot("active", "LOGGED_IN");
		switch (type)
		{
			case GAME_CONTEXT:
				JsonObject session = new JsonObject();
				session.addProperty("world", 301);
				session.addProperty("accountType", "NORMAL");
				snapshot.add("session", session);
				JsonObject player = new JsonObject();
				player.addProperty("name", "Gabs");
				player.addProperty("combatLevel", 126);
				snapshot.add("player", player);
				break;
			case SKILLS:
				JsonArray skills = new JsonArray();
				skills.add(skill("Attack", 80));
				skills.add(skill("Agility", 72));
				snapshot.add("skills", skills);
				break;
			case STATUS_EFFECTS:
				snapshot.add("effects", effects());
				break;
			case CARRIED_ITEMS:
				snapshot.add("containers", containers());
				break;
			default:
				throw new AssertionError(type);
		}
		return snapshot;
	}

	private static JsonObject unavailableContext(String state, String gameState)
	{
		JsonObject snapshot = baseSnapshot(state, gameState);
		JsonObject session = new JsonObject();
		session.add("world", JsonNull.INSTANCE);
		session.add("accountType", JsonNull.INSTANCE);
		snapshot.add("session", session);
		snapshot.add("player", JsonNull.INSTANCE);
		return snapshot;
	}

	private static JsonObject baseSnapshot(String state, String gameState)
	{
		JsonObject snapshot = new JsonObject();
		snapshot.addProperty("state", state);
		JsonObject sample = new JsonObject();
		sample.addProperty("gameState", gameState);
		sample.addProperty("tick", 123);
		snapshot.add("sample", sample);
		return snapshot;
	}

	private static JsonObject skill(String name, int level)
	{
		JsonObject skill = new JsonObject();
		skill.addProperty("name", name);
		skill.addProperty("baseLevel", level);
		skill.addProperty("currentLevel", level);
		skill.addProperty("experience", 1_000_000);
		return skill;
	}

	private static JsonObject effects()
	{
		JsonObject effects = new JsonObject();
		effects.addProperty("availability", "current");
		JsonArray boosts = new JsonArray();
		JsonObject boost = new JsonObject();
		boost.addProperty("skill", "Strength");
		boosts.add(boost);
		effects.add("boosts", boosts);
		JsonArray prayers = new JsonArray();
		prayers.add("protect_from_melee");
		effects.add("activePrayers", prayers);
		JsonObject poison = new JsonObject();
		poison.addProperty("state", "none");
		effects.add("poison", poison);
		effects.add("timers", new JsonArray());
		return effects;
	}

	private static JsonObject containers()
	{
		JsonObject containers = new JsonObject();
		containers.add("inventory", container("inventory"));
		containers.add("equipment", container("weapon"));
		return containers;
	}

	private static JsonObject container(String slotName)
	{
		JsonObject container = new JsonObject();
		container.addProperty("availability", "current");
		JsonArray items = new JsonArray();
		JsonObject item = new JsonObject();
		item.addProperty("slotName", slotName);
		items.add(item);
		container.add("items", items);
		return container;
	}
}
