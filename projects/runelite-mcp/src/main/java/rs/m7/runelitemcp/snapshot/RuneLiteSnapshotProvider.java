package rs.m7.runelitemcp.snapshot;

import com.google.gson.JsonArray;
import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import java.util.Locale;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicBoolean;
import javax.inject.Inject;
import lombok.extern.slf4j.Slf4j;
import net.runelite.api.Actor;
import net.runelite.api.Client;
import net.runelite.api.EquipmentInventorySlot;
import net.runelite.api.GameState;
import net.runelite.api.Item;
import net.runelite.api.ItemComposition;
import net.runelite.api.ItemContainer;
import net.runelite.api.NPC;
import net.runelite.api.Player;
import net.runelite.api.Prayer;
import net.runelite.api.Skill;
import net.runelite.api.Varbits;
import net.runelite.api.coords.WorldPoint;
import net.runelite.api.gameval.InventoryID;
import net.runelite.api.gameval.VarPlayerID;
import net.runelite.api.gameval.VarbitID;
import net.runelite.client.callback.ClientThread;
import net.runelite.client.game.ItemManager;

@Slf4j
@SuppressWarnings("deprecation")
public class RuneLiteSnapshotProvider implements SnapshotProvider
{
	private static final long SNAPSHOT_TIMEOUT_SECONDS = 2;
	private static final long SLOW_SNAPSHOT_NANOS = TimeUnit.MILLISECONDS.toNanos(5);
	private static final long SLOW_WARNING_INTERVAL_NANOS = TimeUnit.MINUTES.toNanos(1);
	private static final int INVENTORY_CAPACITY = 28;
	private static final int EQUIPMENT_CAPACITY = 14;
	private static final int VENOM_THRESHOLD = 1_000_000;
	private static final int VENOM_MAX_DAMAGE = 20;

	private final Client client;
	private final ClientThread clientThread;
	private final ProgressionSnapshotReader progression;
	private final AccountStateSnapshotReader accountState;
	private long lastSlowWarningNanos;

	@Inject
	public RuneLiteSnapshotProvider(Client client, ClientThread clientThread,
		ItemManager itemManager, AccountStateCache accountStateCache)
	{
		this.client = client;
		this.clientThread = clientThread;
		this.progression = new ProgressionSnapshotReader(client);
		this.accountState = new AccountStateSnapshotReader(client, itemManager, accountStateCache);
	}

	RuneLiteSnapshotProvider(Client client, ClientThread clientThread)
	{
		this(client, clientThread, null, new AccountStateCache());
	}

	@Override
	public JsonObject snapshot(SnapshotType type) throws Exception
	{
		return snapshot(type, new JsonObject());
	}

	@Override
	public JsonObject snapshot(SnapshotType type, JsonObject arguments) throws Exception
	{
		CompletableFuture<JsonObject> result = new CompletableFuture<>();
		AtomicBoolean cancelled = new AtomicBoolean();
		clientThread.invoke(() ->
		{
			if (cancelled.get())
			{
				return;
			}
			try
			{
				result.complete(readSnapshot(type, arguments));
			}
			catch (RuntimeException ex)
			{
				result.completeExceptionally(ex);
			}
		});

		try
		{
			JsonObject snapshot = result.get(SNAPSHOT_TIMEOUT_SECONDS, TimeUnit.SECONDS);
			return finishSnapshot(type, arguments, snapshot);
		}
		catch (TimeoutException ex)
		{
			cancelled.set(true);
			throw new IllegalStateException("RuneLite did not produce a client snapshot in time");
		}
	}

	JsonObject readSnapshot(SnapshotType type)
	{
		return readSnapshot(type, new JsonObject());
	}

	JsonObject readSnapshot(SnapshotType type, JsonObject arguments)
	{
		assert client.isClientThread();
		long started = System.nanoTime();

		GameState gameState = client.getGameState();
		Player player = gameState == GameState.LOGGED_IN ? client.getLocalPlayer() : null;
		String state = state(gameState, player != null);
		boolean active = "active".equals(state);

		JsonObject snapshot = new JsonObject();
		snapshot.addProperty("state", state);
		snapshot.add("sample", sample(gameState));

		switch (type)
		{
			case GAME_CONTEXT:
				snapshot.add("session", session(active));
				snapshot.add("player", active ? player(player) : JsonNull.INSTANCE);
				break;
			case SKILLS:
				snapshot.add("skills", skills(active));
				break;
			case STATUS_EFFECTS:
				snapshot.add("effects", effects(active));
				break;
			case CARRIED_ITEMS:
				snapshot.add("containers", containers(active));
				break;
			case QUESTS:
				snapshot.add("quests", active ? progression.quests(arguments) : unavailable());
				break;
			case ACHIEVEMENT_DIARIES:
				snapshot.add("achievementDiaries", active ? progression.diaries(arguments) : unavailable());
				break;
			case COMBAT_ACHIEVEMENTS:
				snapshot.add("combatAchievements", active ? progression.combatAchievements(arguments) : unavailable());
				break;
			case SLAYER:
				snapshot.add("slayer", active ? progression.slayer(arguments) : unavailable());
				break;
			case GRAND_EXCHANGE:
			case STORED_ITEMS:
			case ACCOUNT_WEALTH:
				if (active)
				{
					accountState.observeClientState(type);
					snapshot.addProperty("_accountGeneration", accountState.generation());
				}
				snapshot.add(accountField(type), active ? JsonNull.INSTANCE : unavailable());
				break;
			case COLLECTION_LOG:
				snapshot.add("collectionLog", active ? progression.collectionLog() : unavailable());
				break;
			default:
				throw new IllegalArgumentException("Unsupported snapshot type: " + type);
		}
		long elapsed = System.nanoTime() - started;
		if (elapsed >= SLOW_SNAPSHOT_NANOS
			&& started - lastSlowWarningNanos >= SLOW_WARNING_INTERVAL_NANOS)
		{
			lastSlowWarningNanos = started;
			log.warn("RuneLite MCP {} snapshot took {} ms on the client thread",
				type, TimeUnit.NANOSECONDS.toMillis(elapsed));
		}
		return snapshot;
	}

	private JsonObject finishSnapshot(SnapshotType type, JsonObject arguments, JsonObject snapshot)
	{
		if (!"active".equals(snapshot.get("state").getAsString()))
		{
			return snapshot;
		}
		long accountGeneration = -1;
		if (snapshot.has("_accountGeneration"))
		{
			accountGeneration = snapshot.remove("_accountGeneration").getAsLong();
			if (accountGeneration != accountState.generation())
			{
				throw new IllegalStateException("RuneLite account state changed during the snapshot");
			}
		}
		switch (type)
		{
			case GRAND_EXCHANGE:
				snapshot.add("grandExchange", accountState.grandExchange());
				break;
			case STORED_ITEMS:
				snapshot.add("containers", accountState.storedItems(arguments));
				break;
			case ACCOUNT_WEALTH:
				snapshot.add("wealth", accountState.wealth());
				break;
			default:
				break;
		}
		if (accountGeneration != -1 && accountGeneration != accountState.generation())
		{
			throw new IllegalStateException("RuneLite account state changed during the snapshot");
		}
		return snapshot;
	}

	private static String accountField(SnapshotType type)
	{
		switch (type)
		{
			case GRAND_EXCHANGE:
				return "grandExchange";
			case STORED_ITEMS:
				return "containers";
			case ACCOUNT_WEALTH:
				return "wealth";
			default:
				throw new IllegalArgumentException("Not an account-state snapshot: " + type);
		}
	}

	private static JsonObject unavailable()
	{
		JsonObject value = new JsonObject();
		value.addProperty("availability", "not_logged_in");
		return value;
	}

	private JsonObject sample(GameState gameState)
	{
		JsonObject sample = new JsonObject();
		sample.addProperty("gameState", gameState.name());
		sample.addProperty("tick", client.getTickCount());
		return sample;
	}

	private JsonObject session(boolean active)
	{
		JsonObject session = new JsonObject();
		if (!active)
		{
			session.add("world", JsonNull.INSTANCE);
			session.add("accountType", JsonNull.INSTANCE);
			return session;
		}

		session.addProperty("world", client.getWorld());
		session.addProperty("accountType", accountType(client.getVarbitValue(Varbits.ACCOUNT_TYPE)));
		return session;
	}

	private JsonObject player(Player player)
	{
		JsonObject value = new JsonObject();
		value.addProperty("name", player.getName());
		value.addProperty("combatLevel", player.getCombatLevel());
		value.add("location", location(player.getWorldLocation()));
		value.add("movement", movement(player));
		value.add("interaction", interaction(player.getInteracting()));
		value.add("vitals", vitals());
		return value;
	}

	private static JsonObject location(WorldPoint worldPoint)
	{
		JsonObject location = new JsonObject();
		location.addProperty("x", worldPoint.getX());
		location.addProperty("y", worldPoint.getY());
		location.addProperty("plane", worldPoint.getPlane());
		location.addProperty("regionId", worldPoint.getRegionID());
		return location;
	}

	private JsonObject movement(Player player)
	{
		JsonObject movement = new JsonObject();
		movement.addProperty("moving", client.getLocalDestinationLocation() != null);
		movement.addProperty("animationId", player.getAnimation());
		movement.addProperty("poseAnimationId", player.getPoseAnimation());
		return movement;
	}

	private static JsonObject interaction(Actor actor)
	{
		if (actor == null)
		{
			return null;
		}

		JsonObject interaction = new JsonObject();
		if (actor instanceof NPC)
		{
			NPC npc = (NPC) actor;
			interaction.addProperty("type", "npc");
			interaction.addProperty("id", npc.getId());
			interaction.addProperty("name", npc.getName());
			interaction.addProperty("combatLevel", npc.getCombatLevel());
		}
		else if (actor instanceof Player)
		{
			interaction.addProperty("type", "player");
			interaction.addProperty("combatLevel", actor.getCombatLevel());
		}
		else
		{
			interaction.addProperty("type", "actor");
		}
		return interaction;
	}

	private JsonObject vitals()
	{
		JsonObject vitals = new JsonObject();
		vitals.add("hitpoints", level(Skill.HITPOINTS));
		vitals.add("prayer", level(Skill.PRAYER));
		vitals.addProperty("runEnergyPercent", client.getEnergy() / 100.0);
		vitals.addProperty("specialAttackPercent", client.getVarpValue(VarPlayerID.SA_ENERGY) / 10.0);
		return vitals;
	}

	private JsonObject level(Skill skill)
	{
		JsonObject level = new JsonObject();
		level.addProperty("current", client.getBoostedSkillLevel(skill));
		level.addProperty("max", client.getRealSkillLevel(skill));
		return level;
	}

	private JsonArray skills(boolean active)
	{
		JsonArray skills = new JsonArray();
		if (!active)
		{
			return skills;
		}

		for (Skill skill : Skill.values())
		{
			JsonObject value = new JsonObject();
			value.addProperty("name", skill.getName());
			value.addProperty("baseLevel", client.getRealSkillLevel(skill));
			value.addProperty("currentLevel", client.getBoostedSkillLevel(skill));
			value.addProperty("experience", client.getSkillExperience(skill));
			skills.add(value);
		}
		return skills;
	}

	private JsonObject effects(boolean active)
	{
		JsonObject effects = new JsonObject();
		effects.addProperty("availability", active ? "current" : "not_logged_in");
		effects.add("boosts", active ? boosts() : new JsonArray());
		effects.add("activePrayers", active ? activePrayers() : new JsonArray());
		effects.add("poison", active ? poison() : JsonNull.INSTANCE);
		effects.add("timers", active ? timers() : new JsonArray());
		return effects;
	}

	private JsonArray boosts()
	{
		JsonArray boosts = new JsonArray();
		for (Skill skill : Skill.values())
		{
			if (skill == Skill.OVERALL)
			{
				continue;
			}
			int baseLevel = client.getRealSkillLevel(skill);
			int currentLevel = client.getBoostedSkillLevel(skill);
			if (baseLevel == currentLevel)
			{
				continue;
			}

			JsonObject boost = new JsonObject();
			boost.addProperty("skill", skill.getName());
			boost.addProperty("baseLevel", baseLevel);
			boost.addProperty("currentLevel", currentLevel);
			boost.addProperty("delta", currentLevel - baseLevel);
			boosts.add(boost);
		}
		return boosts;
	}

	private JsonArray activePrayers()
	{
		JsonArray prayers = new JsonArray();
		for (Prayer prayer : Prayer.values())
		{
			if (client.getVarbitValue(prayer.getVarbit()) == 1)
			{
				prayers.add(prayer.name().toLowerCase(Locale.ROOT));
			}
		}
		return prayers;
	}

	private JsonObject poison()
	{
		return poison(client.getVarpValue(VarPlayerID.POISON));
	}

	static JsonObject poison(int value)
	{
		// Matches RuneLite's PoisonPlugin: venom starts at 6, rises by 2, and caps at 20.
		JsonObject poison = new JsonObject();
		if (value >= VENOM_THRESHOLD)
		{
			poison.addProperty("state", "venomed");
			poison.addProperty("nextDamage", Math.min(VENOM_MAX_DAMAGE, (value - VENOM_THRESHOLD + 3) * 2));
		}
		else if (value > 0)
		{
			poison.addProperty("state", "poisoned");
			poison.addProperty("nextDamage", (int) Math.ceil(value / 5.0));
		}
		else
		{
			poison.addProperty("state", "none");
			poison.addProperty("nextDamage", 0);
		}
		return poison;
	}

	private JsonArray timers()
	{
		JsonArray timers = new JsonArray();
		// RuneLite documents stamina, antifire, and super antifire in 10, 30, and
		// 20-tick intervals respectively; divine potion values are already ticks.
		addTimer(timers, "stamina", VarbitID.STAMINA_DURATION, 10);
		addTimer(timers, "antifire", VarbitID.ANTIFIRE_POTION, 30);
		addTimer(timers, "super_antifire", VarbitID.SUPER_ANTIFIRE_POTION, 20);
		addTimer(timers, "divine_attack", VarbitID.DIVINEATTACK_POTION_TIME, 1);
		addTimer(timers, "divine_strength", VarbitID.DIVINESTRENGTH_POTION_TIME, 1);
		addTimer(timers, "divine_defence", VarbitID.DIVINEDEFENCE_POTION_TIME, 1);
		addTimer(timers, "divine_ranging", VarbitID.DIVINERANGE_POTION_TIME, 1);
		addTimer(timers, "divine_magic", VarbitID.DIVINEMAGIC_POTION_TIME, 1);
		addTimer(timers, "divine_combat", VarbitID.DIVINECOMBAT_POTION_TIME, 1);
		addTimer(timers, "divine_bastion", VarbitID.DIVINEBASTION_POTION_TIME, 1);
		addTimer(timers, "divine_battlemage", VarbitID.DIVINEBATTLEMAGE_POTION_TIME, 1);
		return timers;
	}

	private void addTimer(JsonArray timers, String name, int varbit, int tickMultiplier)
	{
		int value = client.getVarbitValue(varbit);
		if (value <= 0)
		{
			return;
		}
		JsonObject timer = new JsonObject();
		timer.addProperty("name", name);
		timer.addProperty("remainingTicks", value * tickMultiplier);
		timers.add(timer);
	}

	private JsonObject containers(boolean active)
	{
		JsonObject containers = new JsonObject();
		containers.add("inventory", container("inventory", InventoryID.INV, INVENTORY_CAPACITY, active));
		containers.add("equipment", container("equipment", InventoryID.WORN, EQUIPMENT_CAPACITY, active));
		return containers;
	}

	private JsonObject container(String name, int inventoryId, int capacity, boolean active)
	{
		if (!active)
		{
			return unavailableContainer("not_logged_in", capacity);
		}

		ItemContainer container = client.getItemContainer(inventoryId);
		if (container == null)
		{
			return unavailableContainer("unavailable", capacity);
		}

		Item[] source = container.getItems();
		JsonArray items = new JsonArray();
		int occupiedSlots = 0;
		long totalQuantity = 0;
		boolean truncated = false;
		for (int slot = 0; slot < source.length; slot++)
		{
			Item item = source[slot];
			if (item == null || item.getId() < 0 || item.getQuantity() <= 0)
			{
				continue;
			}
			occupiedSlots++;
			totalQuantity += item.getQuantity();
			if (slot >= capacity)
			{
				truncated = true;
				continue;
			}

			ItemComposition definition = client.getItemDefinition(item.getId());
			JsonObject value = new JsonObject();
			value.addProperty("slot", slot);
			if ("equipment".equals(name))
			{
				value.addProperty("slotName", equipmentSlotName(slot));
			}
			value.addProperty("id", item.getId());
			value.addProperty("name", definition.getName());
			value.addProperty("quantity", item.getQuantity());
			value.addProperty("noted", definition.getNote() == 799);
			value.addProperty("stackable", definition.isStackable());
			items.add(value);
		}

		JsonObject result = new JsonObject();
		result.addProperty("availability", "current");
		result.addProperty("capacity", capacity);
		result.addProperty("occupiedSlots", occupiedSlots);
		result.addProperty("totalQuantity", totalQuantity);
		result.addProperty("truncated", truncated);
		result.add("items", items);
		return result;
	}

	private static JsonObject unavailableContainer(String availability, int capacity)
	{
		JsonObject result = new JsonObject();
		result.addProperty("availability", availability);
		result.addProperty("capacity", capacity);
		result.add("occupiedSlots", JsonNull.INSTANCE);
		result.add("totalQuantity", JsonNull.INSTANCE);
		result.addProperty("truncated", false);
		result.add("items", new JsonArray());
		return result;
	}

	private static String equipmentSlotName(int slot)
	{
		for (EquipmentInventorySlot value : EquipmentInventorySlot.values())
		{
			if (value.getSlotIdx() == slot)
			{
				return value.name().toLowerCase(Locale.ROOT);
			}
		}
		return "unknown";
	}

	static String state(GameState gameState, boolean hasPlayer)
	{
		if (gameState == GameState.LOGGED_IN && hasPlayer)
		{
			return "active";
		}
		if (gameState == GameState.LOGIN_SCREEN || gameState == GameState.LOGIN_SCREEN_AUTHENTICATOR)
		{
			return "logged_out";
		}
		return "loading";
	}

	static String accountType(int value)
	{
		switch (value)
		{
			case 0:
				return "NORMAL";
			case 1:
				return "IRONMAN";
			case 2:
				return "ULTIMATE_IRONMAN";
			case 3:
				return "HARDCORE_IRONMAN";
			case 4:
				return "GROUP_IRONMAN";
			case 5:
				return "HARDCORE_GROUP_IRONMAN";
			case 6:
				return "UNRANKED_GROUP_IRONMAN";
			default:
				return "UNKNOWN";
		}
	}
}
