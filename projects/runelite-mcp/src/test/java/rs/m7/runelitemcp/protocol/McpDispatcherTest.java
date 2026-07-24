package rs.m7.runelitemcp.protocol;

import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import org.junit.Test;
import rs.m7.runelitemcp.snapshot.SnapshotType;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

public class McpDispatcherTest
{
	private final McpDispatcher dispatcher = new McpDispatcher(McpDispatcherTest::activeSnapshot, new Gson());

	@Test
	public void initializesWithReadCapabilities()
	{
		JsonObject response = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{},\"clientInfo\":{\"name\":\"test\",\"version\":\"1\"}}}"));
		JsonObject result = response.getAsJsonObject("result");
		assertEquals("2025-11-25", result.get("protocolVersion").getAsString());
		assertTrue(result.getAsJsonObject("capabilities").has("tools"));
		assertTrue(result.getAsJsonObject("capabilities").has("resources"));
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
		assertEquals(4, tools.size());
		assertEquals("get_game_context", tools.get(0).getAsJsonObject().get("name").getAsString());
		assertEquals("get_skills", tools.get(1).getAsJsonObject().get("name").getAsString());
		assertEquals("get_status_effects", tools.get(2).getAsJsonObject().get("name").getAsString());
		assertEquals("get_carried_items", tools.get(3).getAsJsonObject().get("name").getAsString());

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
	public void removesProvisionalInterfacesRatherThanAliasingThem()
	{
		for (String name : new String[]{"client_state", "skills"})
		{
			JsonObject oldTool = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":\"" + name + "\",\"arguments\":{}}}"));
			assertTrue(oldTool.getAsJsonObject("result").get("isError").getAsBoolean());
		}

		JsonObject oldResource = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"resources/read\",\"params\":{\"uri\":\"runelite://client/state\"}}"));
		assertEquals(-32602, oldResource.getAsJsonObject("error").get("code").getAsInt());
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
	}

	@Test
	public void rejectsInvalidJsonRpcIds()
	{
		for (String id : new String[]{"true", "[]", "{}"})
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
	public void readsGameContextResource()
	{
		JsonObject response = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"resources/read\",\"params\":{\"uri\":\"runelite://game/context\"}}"));
		String text = response.getAsJsonObject("result").getAsJsonArray("contents")
			.get(0).getAsJsonObject().get("text").getAsString();
		JsonObject context = new JsonParser().parse(text).getAsJsonObject();
		assertEquals("active", context.get("state").getAsString());
		assertFalse(context.has("skills"));
	}

	private void assertInvalidArguments(String name, String arguments)
	{
		JsonObject response = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":13,\"method\":\"tools/call\",\"params\":{\"name\":\"" + name + "\",\"arguments\":" + arguments + "}}"));
		assertEquals(-32602, response.getAsJsonObject("error").get("code").getAsInt());
	}

	private void assertUnavailableContext(JsonObject snapshot, String state, String gameState)
	{
		McpDispatcher stateDispatcher = new McpDispatcher(type -> snapshot, new Gson());
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
