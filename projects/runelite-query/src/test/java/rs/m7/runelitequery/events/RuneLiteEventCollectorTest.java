package rs.m7.runelitequery.events;

import java.lang.reflect.Proxy;
import java.util.Collections;
import java.util.EnumMap;
import java.util.Map;
import net.runelite.api.Actor;
import net.runelite.api.Client;
import net.runelite.api.GameState;
import net.runelite.api.Item;
import net.runelite.api.ItemComposition;
import net.runelite.api.ItemContainer;
import net.runelite.api.Player;
import net.runelite.api.Skill;
import net.runelite.api.coords.WorldPoint;
import net.runelite.api.events.GameStateChanged;
import net.runelite.api.events.ItemContainerChanged;
import net.runelite.api.events.StatChanged;
import net.runelite.api.gameval.InventoryID;
import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertTrue;

public class RuneLiteEventCollectorTest
{
	@Test
	public void collectsNetChangesAndClearsHistoryOnLogout()
	{
		FakeState state = new FakeState();
		RuneLiteEventCollector collector = new RuneLiteEventCollector(client(state), null);
		EventHistory history = new EventHistory();
		collector.startOnClientThread(history);

		EventPage initial = latest(history);
		assertEquals(1, initial.getEvents().size());
		assertEquals(EventType.MOVEMENT_CHANGED, initial.getEvents().get(0).getType());

		state.tick++;
		state.experience.put(Skill.ATTACK, 100);
		state.currentLevels.put(Skill.ATTACK, 2);
		collector.onStatChanged(new StatChanged(Skill.ATTACK, 100, 1, 2));
		collector.onGameTick();
		EventRecord skill = lastOfType(latest(history), EventType.SKILL_CHANGED);
		assertEquals(1, skill.toJson().getAsJsonObject("data").get("levelDelta").getAsInt());
		assertEquals(100, skill.toJson().getAsJsonObject("data").get("experienceDelta").getAsInt());

		state.tick++;
		state.inventory[0] = new Item(995, 100);
		collector.onItemContainerChanged(new ItemContainerChanged(InventoryID.INV,
			itemContainer(state.inventory)));
		collector.onGameTick();
		EventRecord inventory = lastOfType(latest(history), EventType.INVENTORY_CHANGED);
		assertEquals(995, inventory.toJson().getAsJsonObject("data").getAsJsonArray("changes")
			.get(0).getAsJsonObject().getAsJsonObject("after").get("id").getAsInt());

		String generation = history.getGeneration();
		state.tick++;
		state.gameState = GameState.LOGIN_SCREEN;
		GameStateChanged logout = new GameStateChanged();
		logout.setGameState(GameState.LOGIN_SCREEN);
		collector.onGameStateChanged(logout);
		assertNotEquals(generation, history.getGeneration());
		EventPage loggedOut = latest(history);
		assertEquals("logged_out", loggedOut.getMetadata().getState());
		assertEquals(1, loggedOut.getEvents().size());
		assertEquals(EventType.GAME_STATE_CHANGED, loggedOut.getEvents().get(0).getType());
	}

	@Test
	public void omitsPlayerTargetIdentityAndDoesNotSurviveRestart()
	{
		FakeState state = new FakeState();
		RuneLiteEventCollector collector = new RuneLiteEventCollector(client(state), null);
		EventHistory first = new EventHistory();
		collector.startOnClientThread(first);

		state.tick++;
		state.interaction[0] = playerTarget("Secret Name", 88);
		collector.onGameTick();
		EventRecord interaction = lastOfType(latest(first), EventType.INTERACTION_CHANGED);
		String json = interaction.toJson().toString();
		assertTrue(json.contains("\"type\":\"player\""));
		assertTrue(json.contains("\"combatLevel\":88"));
		assertFalse(json.contains("Secret Name"));
		assertFalse(json.contains("\"id\""));

		String generation = first.getGeneration();
		state.localName[0] = null;
		state.tick++;
		collector.onGameTick();
		assertEquals(generation, first.getGeneration());
		state.localName[0] = "Other account";
		state.tick++;
		collector.onGameTick();
		assertNotEquals(generation, first.getGeneration());

		collector.stop();
		state.interaction[0] = null;
		EventHistory second = new EventHistory();
		collector.startOnClientThread(second);
		assertNotEquals(first.getGeneration(), second.getGeneration());
		assertFalse(hasType(latest(second), EventType.INTERACTION_CHANGED));
	}

	private static EventPage latest(EventHistory history)
	{
		return history.query(new EventQuery(null, null, null, Collections.emptySet(), 100));
	}

	private static boolean hasType(EventPage page, EventType type)
	{
		for (EventRecord event : page.getEvents())
		{
			if (event.getType() == type)
			{
				return true;
			}
		}
		return false;
	}

	private static EventRecord lastOfType(EventPage page, EventType type)
	{
		EventRecord found = null;
		for (EventRecord event : page.getEvents())
		{
			if (event.getType() == type)
			{
				found = event;
			}
		}
		if (found == null)
		{
			throw new AssertionError("Missing event " + type);
		}
		return found;
	}

	private static Client client(FakeState state)
	{
		return (Client) Proxy.newProxyInstance(
			Client.class.getClassLoader(),
			new Class<?>[]{Client.class},
			(proxy, method, args) ->
			{
				switch (method.getName())
				{
					case "getGameState":
						return state.gameState;
					case "getTickCount":
						return state.tick;
					case "getLocalPlayer":
						return state.player;
					case "getRealSkillLevel":
						return state.baseLevels.get((Skill) args[0]);
					case "getBoostedSkillLevel":
						return state.currentLevels.get((Skill) args[0]);
					case "getSkillExperience":
						return state.experience.get((Skill) args[0]);
					case "getItemContainer":
						return (int) args[0] == InventoryID.INV
							? itemContainer(state.inventory) : itemContainer(state.equipment);
					case "getItemDefinition":
						return itemDefinition((int) args[0]);
					case "getLocalDestinationLocation":
						return null;
					default:
						throw new AssertionError("Unexpected Client method: " + method.getName());
				}
			}
		);
	}

	private static Player playerTarget(String name, int combatLevel)
	{
		return (Player) Proxy.newProxyInstance(
			Player.class.getClassLoader(), new Class<?>[]{Player.class},
			(proxy, method, args) ->
			{
				if ("getName".equals(method.getName()))
				{
					return name;
				}
				if ("getCombatLevel".equals(method.getName()))
				{
					return combatLevel;
				}
				throw new AssertionError("Unexpected target Player method: " + method.getName());
			}
		);
	}

	private static ItemContainer itemContainer(Item[] items)
	{
		return (ItemContainer) Proxy.newProxyInstance(
			ItemContainer.class.getClassLoader(), new Class<?>[]{ItemContainer.class},
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
			ItemComposition.class.getClassLoader(), new Class<?>[]{ItemComposition.class},
			(proxy, method, args) ->
			{
				if ("getName".equals(method.getName()))
				{
					return id == 995 ? "Coins" : "Item " + id;
				}
				throw new AssertionError("Unexpected ItemComposition method: " + method.getName());
			}
		);
	}

	private static final class FakeState
	{
		private GameState gameState = GameState.LOGGED_IN;
		private int tick = 1;
		private final Map<Skill, Integer> experience = new EnumMap<>(Skill.class);
		private final Map<Skill, Integer> baseLevels = new EnumMap<>(Skill.class);
		private final Map<Skill, Integer> currentLevels = new EnumMap<>(Skill.class);
		private final Item[] inventory = new Item[28];
		private final Item[] equipment = new Item[14];
		private final Actor[] interaction = {null};
		private final String[] localName = {"Gabs"};
		private final Player player;

		private FakeState()
		{
			for (Skill skill : Skill.values())
			{
				experience.put(skill, 0);
				baseLevels.put(skill, 1);
				currentLevels.put(skill, 1);
			}
			player = (Player) Proxy.newProxyInstance(
				Player.class.getClassLoader(), new Class<?>[]{Player.class},
				(proxy, method, args) ->
				{
					switch (method.getName())
					{
						case "getName":
							return localName[0];
						case "getCombatLevel":
							return 88;
						case "getWorldLocation":
							return new WorldPoint(3200, 3200, 0);
						case "getAnimation":
							return -1;
						case "getInteracting":
							return interaction[0];
						default:
							throw new AssertionError("Unexpected local Player method: " + method.getName());
					}
				}
			);
		}
	}
}
