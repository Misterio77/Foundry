package rs.m7.runelitemcp.snapshot;

import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.lang.reflect.Proxy;
import net.runelite.api.Client;
import net.runelite.api.GameState;
import net.runelite.api.Player;
import net.runelite.api.coords.WorldPoint;
import org.junit.Test;
import rs.m7.runelitemcp.protocol.DispatchResult;
import rs.m7.runelitemcp.protocol.McpDispatcher;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

public class RuneLiteSnapshotProviderTest
{
	@Test
	public void normalizesEveryRuneLiteGameState()
	{
		assertEquals("active", RuneLiteSnapshotProvider.state(GameState.LOGGED_IN, true));
		assertEquals("loading", RuneLiteSnapshotProvider.state(GameState.LOGGED_IN, false));
		assertEquals("logged_out", RuneLiteSnapshotProvider.state(GameState.LOGIN_SCREEN, false));
		assertEquals("logged_out", RuneLiteSnapshotProvider.state(GameState.LOGIN_SCREEN_AUTHENTICATOR, false));
		assertEquals("loading", RuneLiteSnapshotProvider.state(GameState.UNKNOWN, false));
		assertEquals("loading", RuneLiteSnapshotProvider.state(GameState.STARTING, false));
		assertEquals("loading", RuneLiteSnapshotProvider.state(GameState.LOGGING_IN, false));
		assertEquals("loading", RuneLiteSnapshotProvider.state(GameState.LOADING, false));
		assertEquals("loading", RuneLiteSnapshotProvider.state(GameState.CONNECTION_LOST, false));
		assertEquals("loading", RuneLiteSnapshotProvider.state(GameState.HOPPING, false));
	}

	@Test
	public void clearsPlayerBoundDataAcrossClientTransitions()
	{
		GameState[] gameState = {GameState.LOGGED_IN};
		Player player = (Player) Proxy.newProxyInstance(
			Player.class.getClassLoader(),
			new Class<?>[]{Player.class},
			(proxy, method, args) ->
			{
				switch (method.getName())
				{
					case "getName":
						return "Gabs";
					case "getCombatLevel":
						return 126;
					case "getWorldLocation":
						return new WorldPoint(3200, 3200, 0);
					case "getAnimation":
						return -1;
					case "getPoseAnimation":
						return 808;
					case "getInteracting":
						return null;
					default:
						throw new AssertionError("Unexpected Player method: " + method.getName());
				}
			}
		);
		Client client = (Client) Proxy.newProxyInstance(
			Client.class.getClassLoader(),
			new Class<?>[]{Client.class},
			(proxy, method, args) ->
			{
				switch (method.getName())
				{
					case "isClientThread":
						return true;
					case "getGameState":
						return gameState[0];
					case "getLocalPlayer":
						return player;
					case "getTickCount":
						return 123;
					case "getWorld":
						return 301;
					case "getVarbitValue":
						return 0;
					case "getLocalDestinationLocation":
						return null;
					case "getEnergy":
						return 10_000;
					case "getVarpValue":
						return 1_000;
					case "getBoostedSkillLevel":
					case "getRealSkillLevel":
						return 99;
					case "getSkillExperience":
						return 13_034_431;
					default:
						throw new AssertionError("Unexpected Client method: " + method.getName());
				}
			}
		);
		RuneLiteSnapshotProvider provider = new RuneLiteSnapshotProvider(client, null);

		JsonObject active = provider.readSnapshot();
		assertEquals("active", active.get("state").getAsString());
		assertEquals("Gabs", active.getAsJsonObject("player").get("name").getAsString());
		assertTrue(active.getAsJsonArray("skills").size() > 0);

		McpDispatcher dispatcher = new McpDispatcher(provider::readSnapshot, new Gson());
		DispatchResult response = dispatcher.dispatch("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"get_game_context\",\"arguments\":{}}}");
		JsonObject serialized = new JsonParser().parse(response.getBody()).getAsJsonObject()
			.getAsJsonObject("result").getAsJsonObject("structuredContent");
		assertTrue(serialized.getAsJsonObject("player").get("interaction").isJsonNull());

		gameState[0] = GameState.HOPPING;
		JsonObject loading = provider.readSnapshot();
		assertEquals("loading", loading.get("state").getAsString());
		assertTrue(loading.get("player").isJsonNull());
		assertTrue(loading.getAsJsonObject("session").get("world").isJsonNull());
		assertEquals(0, loading.getAsJsonArray("skills").size());

		gameState[0] = GameState.LOGIN_SCREEN;
		JsonObject loggedOut = provider.readSnapshot();
		assertEquals("logged_out", loggedOut.get("state").getAsString());
		assertTrue(loggedOut.get("player").isJsonNull());
		assertTrue(loggedOut.getAsJsonObject("session").get("accountType").isJsonNull());
		assertEquals(0, loggedOut.getAsJsonArray("skills").size());
	}

	@Test
	public void namesAllDocumentedAccountTypes()
	{
		assertEquals("NORMAL", RuneLiteSnapshotProvider.accountType(0));
		assertEquals("IRONMAN", RuneLiteSnapshotProvider.accountType(1));
		assertEquals("ULTIMATE_IRONMAN", RuneLiteSnapshotProvider.accountType(2));
		assertEquals("HARDCORE_IRONMAN", RuneLiteSnapshotProvider.accountType(3));
		assertEquals("GROUP_IRONMAN", RuneLiteSnapshotProvider.accountType(4));
		assertEquals("HARDCORE_GROUP_IRONMAN", RuneLiteSnapshotProvider.accountType(5));
		assertEquals("UNRANKED_GROUP_IRONMAN", RuneLiteSnapshotProvider.accountType(6));
		assertEquals("UNKNOWN", RuneLiteSnapshotProvider.accountType(7));
	}
}
