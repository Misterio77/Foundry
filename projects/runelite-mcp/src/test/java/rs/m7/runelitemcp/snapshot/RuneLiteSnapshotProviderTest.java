package rs.m7.runelitemcp.snapshot;

import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.lang.reflect.Proxy;
import net.runelite.api.Client;
import net.runelite.api.GameState;
import net.runelite.api.Item;
import net.runelite.api.ItemComposition;
import net.runelite.api.ItemContainer;
import net.runelite.api.Player;
import net.runelite.api.Prayer;
import net.runelite.api.Skill;
import net.runelite.api.coords.WorldPoint;
import net.runelite.api.gameval.InventoryID;
import net.runelite.api.gameval.VarPlayerID;
import net.runelite.api.gameval.VarbitID;
import org.junit.Test;
import rs.m7.runelitemcp.events.EventHistory;
import rs.m7.runelitemcp.protocol.DispatchResult;
import rs.m7.runelitemcp.protocol.McpDispatcher;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
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
	public void producesFocusedSnapshotsAndClearsPlayerDataAcrossTransitions()
	{
		GameState[] gameState = {GameState.LOGGED_IN};
		Player player = player();
		ItemContainer inventory = itemContainer(28, 0, new Item(995, 1_000));
		ItemContainer equipment = itemContainer(14, 3, new Item(4151, 1));
		Client client = client(gameState, player, inventory, equipment);
		RuneLiteSnapshotProvider provider = new RuneLiteSnapshotProvider(client, null);

		JsonObject context = provider.readSnapshot(SnapshotType.GAME_CONTEXT);
		assertEquals("active", context.get("state").getAsString());
		assertEquals("Gabs", context.getAsJsonObject("player").get("name").getAsString());
		assertFalse(context.has("skills"));

		JsonObject skills = provider.readSnapshot(SnapshotType.SKILLS);
		assertTrue(skills.getAsJsonArray("skills").size() > 0);
		assertFalse(skills.has("player"));

		JsonObject effects = provider.readSnapshot(SnapshotType.STATUS_EFFECTS).getAsJsonObject("effects");
		assertEquals("current", effects.get("availability").getAsString());
		assertEquals("none", effects.getAsJsonObject("poison").get("state").getAsString());
		assertEquals("Strength", effects.getAsJsonArray("boosts").get(0).getAsJsonObject().get("skill").getAsString());
		assertEquals(6, effects.getAsJsonArray("boosts").get(0).getAsJsonObject().get("delta").getAsInt());
		assertTrue(effects.getAsJsonArray("activePrayers").contains(new com.google.gson.JsonPrimitive("protect_from_melee")));
		assertEquals("stamina", effects.getAsJsonArray("timers").get(0).getAsJsonObject().get("name").getAsString());
		assertEquals(20, effects.getAsJsonArray("timers").get(0).getAsJsonObject().get("remainingTicks").getAsInt());
		assertEquals(30, effects.getAsJsonArray("timers").get(1).getAsJsonObject().get("remainingTicks").getAsInt());

		JsonObject containers = provider.readSnapshot(SnapshotType.CARRIED_ITEMS).getAsJsonObject("containers");
		JsonObject inventoryResult = containers.getAsJsonObject("inventory");
		assertEquals("Coins", inventoryResult.getAsJsonArray("items").get(0).getAsJsonObject().get("name").getAsString());
		assertEquals(1_000, inventoryResult.get("totalQuantity").getAsInt());
		JsonObject weapon = containers.getAsJsonObject("equipment").getAsJsonArray("items").get(0).getAsJsonObject();
		assertEquals("weapon", weapon.get("slotName").getAsString());
		assertEquals("Abyssal whip", weapon.get("name").getAsString());

		McpDispatcher dispatcher = new McpDispatcher(provider::readSnapshot, new EventHistory(), new Gson());
		DispatchResult response = dispatcher.dispatch("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"get_game_context\",\"arguments\":{}}}");
		JsonObject serialized = new JsonParser().parse(response.getBody()).getAsJsonObject()
			.getAsJsonObject("result").getAsJsonObject("structuredContent");
		assertTrue(serialized.getAsJsonObject("player").get("interaction").isJsonNull());

		gameState[0] = GameState.HOPPING;
		JsonObject loading = provider.readSnapshot(SnapshotType.GAME_CONTEXT);
		assertEquals("loading", loading.get("state").getAsString());
		assertTrue(loading.get("player").isJsonNull());
		assertTrue(loading.getAsJsonObject("session").get("world").isJsonNull());
		JsonObject loadingInventory = provider.readSnapshot(SnapshotType.CARRIED_ITEMS)
			.getAsJsonObject("containers").getAsJsonObject("inventory");
		assertEquals("not_logged_in", loadingInventory.get("availability").getAsString());
		assertTrue(loadingInventory.get("occupiedSlots").isJsonNull());
		JsonObject loadingEffects = provider.readSnapshot(SnapshotType.STATUS_EFFECTS).getAsJsonObject("effects");
		assertEquals("not_logged_in", loadingEffects.get("availability").getAsString());
		assertEquals(0, loadingEffects.getAsJsonArray("boosts").size());
		assertEquals(0, loadingEffects.getAsJsonArray("activePrayers").size());
		assertTrue(loadingEffects.get("poison").isJsonNull());
		assertEquals(0, loadingEffects.getAsJsonArray("timers").size());

		gameState[0] = GameState.LOGGED_IN;
		Item[] oversizedItems = new Item[30];
		oversizedItems[0] = new Item(995, 10);
		oversizedItems[29] = new Item(995, 20);
		RuneLiteSnapshotProvider boundedProvider = new RuneLiteSnapshotProvider(
			client(gameState, player, itemContainer(oversizedItems), null), null);
		JsonObject boundedInventory = boundedProvider.readSnapshot(SnapshotType.CARRIED_ITEMS)
			.getAsJsonObject("containers").getAsJsonObject("inventory");
		assertTrue(boundedInventory.get("truncated").getAsBoolean());
		assertEquals(2, boundedInventory.get("occupiedSlots").getAsInt());
		assertEquals(30, boundedInventory.get("totalQuantity").getAsInt());
		assertEquals(1, boundedInventory.getAsJsonArray("items").size());
		assertEquals("unavailable", boundedProvider.readSnapshot(SnapshotType.CARRIED_ITEMS)
			.getAsJsonObject("containers").getAsJsonObject("equipment").get("availability").getAsString());

		gameState[0] = GameState.LOGIN_SCREEN;
		JsonObject loggedOut = provider.readSnapshot(SnapshotType.GAME_CONTEXT);
		assertEquals("logged_out", loggedOut.get("state").getAsString());
		assertTrue(loggedOut.get("player").isJsonNull());
		assertTrue(loggedOut.getAsJsonObject("session").get("accountType").isJsonNull());
	}

	@Test
	public void mapsPoisonAndVenomDamage()
	{
		assertEquals("none", RuneLiteSnapshotProvider.poison(0).get("state").getAsString());
		assertEquals("none", RuneLiteSnapshotProvider.poison(-1).get("state").getAsString());
		assertEquals(4, RuneLiteSnapshotProvider.poison(20).get("nextDamage").getAsInt());
		assertEquals(6, RuneLiteSnapshotProvider.poison(1_000_000).get("nextDamage").getAsInt());
		assertEquals(20, RuneLiteSnapshotProvider.poison(1_000_020).get("nextDamage").getAsInt());
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

	private static Player player()
	{
		return (Player) Proxy.newProxyInstance(
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
	}

	private static Client client(GameState[] gameState, Player player, ItemContainer inventory, ItemContainer equipment)
	{
		return (Client) Proxy.newProxyInstance(
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
					case "getLocalDestinationLocation":
						return null;
					case "getEnergy":
						return 10_000;
					case "getVarbitValue":
						int varbit = (int) args[0];
						if (varbit == Prayer.PROTECT_FROM_MELEE.getVarbit())
						{
							return 1;
						}
						if (varbit == VarbitID.STAMINA_DURATION)
						{
							return 2;
						}
						if (varbit == VarbitID.ANTIFIRE_POTION)
						{
							return 1;
						}
						return 0;
					case "getVarpValue":
						return (int) args[0] == VarPlayerID.SA_ENERGY ? 1_000 : 0;
					case "getBoostedSkillLevel":
						return args[0] == Skill.STRENGTH ? 105 : 99;
					case "getRealSkillLevel":
						return 99;
					case "getSkillExperience":
						return 13_034_431;
					case "getItemContainer":
						return (int) args[0] == InventoryID.INV ? inventory : equipment;
					case "getItemDefinition":
						return itemDefinition((int) args[0]);
					default:
						throw new AssertionError("Unexpected Client method: " + method.getName());
				}
			}
		);
	}

	private static ItemContainer itemContainer(int size, int occupiedSlot, Item item)
	{
		Item[] items = new Item[size];
		items[occupiedSlot] = item;
		return itemContainer(items);
	}

	private static ItemContainer itemContainer(Item[] items)
	{
		return (ItemContainer) Proxy.newProxyInstance(
			ItemContainer.class.getClassLoader(),
			new Class<?>[]{ItemContainer.class},
			(proxy, method, args) ->
			{
				if ("getItems".equals(method.getName()))
				{
					return items;
				}
				throw new AssertionError("Unexpected ItemContainer method: " + method.getName());
			}
		);
	}

	private static ItemComposition itemDefinition(int id)
	{
		return (ItemComposition) Proxy.newProxyInstance(
			ItemComposition.class.getClassLoader(),
			new Class<?>[]{ItemComposition.class},
			(proxy, method, args) ->
			{
				switch (method.getName())
				{
					case "getName":
						return id == 995 ? "Coins" : "Abyssal whip";
					case "getNote":
						return -1;
					case "isStackable":
						return id == 995;
					default:
						throw new AssertionError("Unexpected ItemComposition method: " + method.getName());
				}
			}
		);
	}
}
