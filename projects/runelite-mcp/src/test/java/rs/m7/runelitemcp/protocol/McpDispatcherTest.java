package rs.m7.runelitemcp.protocol;

import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

public class McpDispatcherTest
{
	private final McpDispatcher dispatcher = new McpDispatcher(McpDispatcherTest::snapshot, new Gson());

	@Test
	public void initializesWithReadCapabilities()
	{
		JsonObject response = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\"}}"));
		JsonObject result = response.getAsJsonObject("result");
		assertEquals("2025-11-25", result.get("protocolVersion").getAsString());
		assertTrue(result.getAsJsonObject("capabilities").has("tools"));
		assertTrue(result.getAsJsonObject("capabilities").has("resources"));
		assertTrue(result.getAsJsonObject("capabilities").has("prompts"));
	}

	@Test
	public void rejectsLegacyProtocolVersionsRatherThanCarryingCompatibilityPaths()
	{
		JsonObject response = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\"}}"));
		assertEquals(-32602, response.getAsJsonObject("error").get("code").getAsInt());
	}

	@Test
	public void listsAndCallsToolsWithStructuredContent()
	{
		JsonObject listed = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}"));
		assertEquals(2, listed.getAsJsonObject("result").getAsJsonArray("tools").size());

		JsonObject called = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"skills\",\"arguments\":{\"names\":[\"Agility\"]}}}"));
		JsonObject result = called.getAsJsonObject("result");
		JsonArray skills = result.getAsJsonObject("structuredContent").getAsJsonArray("skills");
		assertEquals(1, skills.size());
		assertEquals("Agility", skills.get(0).getAsJsonObject().get("name").getAsString());
		assertFalse(result.has("isError"));
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

		JsonObject unknown = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"unknown\"}"));
		assertEquals(-32601, unknown.getAsJsonObject("error").get("code").getAsInt());
	}

	@Test
	public void readsClientStateResource()
	{
		JsonObject response = response(dispatch("{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"resources/read\",\"params\":{\"uri\":\"runelite://client/state\"}}"));
		String text = response.getAsJsonObject("result").getAsJsonArray("contents")
			.get(0).getAsJsonObject().get("text").getAsString();
		assertEquals("LOGGED_IN", new JsonParser().parse(text).getAsJsonObject().get("gameState").getAsString());
	}

	private DispatchResult dispatch(String request)
	{
		return dispatcher.dispatch(request);
	}

	private static JsonObject response(DispatchResult result)
	{
		assertEquals(200, result.getStatus());
		return new JsonParser().parse(result.getBody()).getAsJsonObject();
	}

	private static JsonObject snapshot()
	{
		JsonObject snapshot = new JsonObject();
		snapshot.addProperty("gameState", "LOGGED_IN");
		snapshot.addProperty("world", 301);
		JsonArray skills = new JsonArray();
		skills.add(skill("Attack", 80));
		skills.add(skill("Agility", 72));
		snapshot.add("skills", skills);
		return snapshot;
	}

	private static JsonObject skill(String name, int level)
	{
		JsonObject skill = new JsonObject();
		skill.addProperty("name", name);
		skill.addProperty("realLevel", level);
		skill.addProperty("boostedLevel", level);
		skill.addProperty("experience", 1_000_000);
		return skill;
	}
}
