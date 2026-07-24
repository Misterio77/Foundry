package rs.m7.runelitemcp.events;

import java.util.ArrayList;
import java.util.EnumMap;
import java.util.EnumSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
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
import net.runelite.api.Skill;
import net.runelite.api.coords.WorldPoint;
import net.runelite.api.events.GameStateChanged;
import net.runelite.api.events.ItemContainerChanged;
import net.runelite.api.events.StatChanged;
import net.runelite.api.gameval.InventoryID;
import net.runelite.client.callback.ClientThread;
import rs.m7.runelitemcp.events.EventPayloads.ContainerChange;
import rs.m7.runelitemcp.events.EventPayloads.GameStateChange;
import rs.m7.runelitemcp.events.EventPayloads.InteractionChange;
import rs.m7.runelitemcp.events.EventPayloads.ItemChange;
import rs.m7.runelitemcp.events.EventPayloads.ItemValue;
import rs.m7.runelitemcp.events.EventPayloads.Location;
import rs.m7.runelitemcp.events.EventPayloads.MovementChange;
import rs.m7.runelitemcp.events.EventPayloads.SkillChange;
import rs.m7.runelitemcp.events.EventPayloads.Target;

@Slf4j
public class RuneLiteEventCollector
{
	private static final int INVENTORY_CAPACITY = 28;
	private static final int EQUIPMENT_CAPACITY = 14;
	private static final int FULL_RECONCILIATION_TICKS = 10;
	private static final int NAME_CACHE_CAPACITY = 256;
	private static final int MAX_NAME_LOOKUPS_PER_TICK = 8;
	private static final long NAME_LOOKUP_BUDGET_NANOS = 1_000_000;
	private static final long SLOW_RECONCILIATION_NANOS = 5_000_000;
	private static final long WARNING_INTERVAL_NANOS = 60_000_000_000L;

	private final Client client;
	private final ClientThread clientThread;
	private final EnumSet<Skill> dirtySkills = EnumSet.noneOf(Skill.class);
	private final EnumMap<Skill, SkillState> skills = new EnumMap<>(Skill.class);
	private final LinkedHashMap<Integer, String> itemNames = new LinkedHashMap<Integer, String>(32, 0.75f, true)
	{
		@Override
		protected boolean removeEldestEntry(Map.Entry<Integer, String> eldest)
		{
			return size() > NAME_CACHE_CAPACITY;
		}
	};

	private volatile EventHistory history;
	private long epoch;
	private GameState trackedState = GameState.UNKNOWN;
	private boolean loggedOutBoundary;
	private String playerName;
	private boolean inventoryDirty;
	private boolean equipmentDirty;
	private ItemState[] inventory;
	private ItemState[] equipment;
	private MovementState movement;
	private Target interaction;
	private long lastWarningNanos;
	private int nameLookups;
	private long nameLookupStartNanos;

	@Inject
	public RuneLiteEventCollector(Client client, ClientThread clientThread)
	{
		this.client = client;
		this.clientThread = clientThread;
	}

	public synchronized void start(EventHistory history)
	{
		prepareStart(history);
		long startEpoch = epoch;
		EventHistory startHistory = history;
		clientThread.invoke(() -> initializeOnClientThread(startEpoch, startHistory));
	}

	void startOnClientThread(EventHistory history)
	{
		synchronized (this)
		{
			prepareStart(history);
		}
		initializeOnClientThread(epoch, history);
	}

	private void prepareStart(EventHistory history)
	{
		this.history = Objects.requireNonNull(history);
		epoch++;
		clearBaselines(true);
		trackedState = GameState.UNKNOWN;
		loggedOutBoundary = false;
	}

	public synchronized void stop()
	{
		epoch++;
		history = null;
		clearBaselines(true);
		trackedState = GameState.UNKNOWN;
		loggedOutBoundary = false;
	}

	public synchronized void onGameStateChanged(GameStateChanged event)
	{
		if (history == null)
		{
			return;
		}
		GameState current = client.getGameState();
		if (event.getGameState() != current)
		{
			log.debug("Ignoring stale RuneLite game-state callback {} while client is {}", event.getGameState(), current);
		}
		processState(current);
	}

	public synchronized void onStatChanged(StatChanged event)
	{
		if (history != null)
		{
			dirtySkills.add(event.getSkill());
		}
	}

	public synchronized void onItemContainerChanged(ItemContainerChanged event)
	{
		if (history == null)
		{
			return;
		}
		if (event.getContainerId() == InventoryID.INV)
		{
			inventoryDirty = true;
		}
		else if (event.getContainerId() == InventoryID.WORN)
		{
			equipmentDirty = true;
		}
	}

	public synchronized void onGameTick()
	{
		EventHistory currentHistory = history;
		if (currentHistory == null)
		{
			return;
		}
		long started = System.nanoTime();
		nameLookups = 0;
		nameLookupStartNanos = 0;
		processState(client.getGameState());

		Player player = activePlayer();
		if (player == null)
		{
			currentHistory.updateState(metadata(null));
			warnIfSlow(started);
			return;
		}
		String currentName = player.getName();
		if (currentName != null)
		{
			if (playerName != null && !Objects.equals(playerName, currentName))
			{
				epoch++;
				clearBaselines(true);
				currentHistory.resetAndAppend(metadata(player), null);
			}
			playerName = currentName;
		}

		boolean full = client.getTickCount() % FULL_RECONCILIATION_TICKS == 0;
		List<PendingEvent> events = new ArrayList<>();
		reconcileSkills(events, full);
		reconcileContainer(events, false, full || inventoryDirty);
		reconcileContainer(events, true, full || equipmentDirty);
		reconcileMovement(events, player);
		reconcileInteraction(events, player);
		inventoryDirty = false;
		equipmentDirty = false;
		dirtySkills.clear();

		EventMetadata metadata = metadata(player);
		if (events.isEmpty())
		{
			currentHistory.updateState(metadata);
		}
		else
		{
			currentHistory.appendBatch(metadata, events);
		}
		warnIfSlow(started);
	}

	private synchronized void initializeOnClientThread(long startEpoch, EventHistory startHistory)
	{
		if (history != startHistory || epoch != startEpoch)
		{
			return;
		}
		trackedState = client.getGameState();
		loggedOutBoundary = isLoginScreen(trackedState);
		clearBaselines(false);
		Player player = activePlayer();
		playerName = player == null ? null : player.getName();
		startHistory.updateState(metadata(player));
		onGameTick();
	}

	private void processState(GameState current)
	{
		EventHistory currentHistory = history;
		if (currentHistory == null || current == trackedState)
		{
			return;
		}
		GameState previous = trackedState;
		trackedState = current;
		Player player = activePlayer();
		EventMetadata metadata = metadata(player);
		PendingEvent transition = new PendingEvent(EventType.GAME_STATE_CHANGED, client.getTickCount(),
			new GameStateChange(previous.name(), current.name(), metadata.getState()));

		if (isLoginScreen(current) && !loggedOutBoundary)
		{
			epoch++;
			clearBaselines(true);
			loggedOutBoundary = true;
			currentHistory.resetAndAppend(metadata, transition);
		}
		else
		{
			if (!isLoginScreen(current))
			{
				loggedOutBoundary = false;
			}
			if (current != GameState.LOGGED_IN || player == null)
			{
				clearBaselines(false);
			}
			currentHistory.appendBatch(metadata, java.util.Collections.singletonList(transition));
		}
	}

	private void reconcileSkills(List<PendingEvent> events, boolean full)
	{
		for (Skill skill : Skill.values())
		{
			if (!full && !dirtySkills.contains(skill) && skills.containsKey(skill))
			{
				continue;
			}
			SkillState before = skills.get(skill);
			SkillState after = new SkillState(
				client.getRealSkillLevel(skill),
				client.getBoostedSkillLevel(skill),
				client.getSkillExperience(skill)
			);
			skills.put(skill, after);
			if (before != null && !before.equals(after))
			{
				events.add(new PendingEvent(EventType.SKILL_CHANGED, client.getTickCount(),
					new SkillChange(skill.getName(), after.baseLevel, after.currentLevel,
						after.currentLevel - before.currentLevel, after.experience,
						after.experience - before.experience)));
			}
		}
	}

	private void reconcileContainer(List<PendingEvent> events, boolean worn, boolean dirty)
	{
		ItemState[] before = worn ? equipment : inventory;
		if (!dirty && before != null)
		{
			return;
		}
		int capacity = worn ? EQUIPMENT_CAPACITY : INVENTORY_CAPACITY;
		ItemState[] after = readContainer(worn ? InventoryID.WORN : InventoryID.INV, capacity);
		if (after == null)
		{
			return;
		}
		if (before != null)
		{
			List<ItemChange> changes = new ArrayList<>();
			for (int slot = 0; slot < capacity; slot++)
			{
				if (!Objects.equals(before[slot], after[slot]))
				{
					changes.add(new ItemChange(slot, worn ? equipmentSlotName(slot) : null,
						itemValue(before[slot]), itemValue(after[slot])));
				}
			}
			if (!changes.isEmpty())
			{
				events.add(new PendingEvent(worn ? EventType.EQUIPMENT_CHANGED : EventType.INVENTORY_CHANGED,
					client.getTickCount(), new ContainerChange(changes, false, capacity)));
			}
		}
		if (worn)
		{
			equipment = after;
		}
		else
		{
			inventory = after;
		}
	}

	private ItemState[] readContainer(int id, int capacity)
	{
		ItemContainer container = client.getItemContainer(id);
		if (container == null)
		{
			return null;
		}
		Item[] source = container.getItems();
		ItemState[] values = new ItemState[capacity];
		for (int slot = 0; slot < Math.min(source.length, capacity); slot++)
		{
			Item item = source[slot];
			if (item != null && item.getId() > 0 && item.getQuantity() > 0)
			{
				values[slot] = new ItemState(item.getId(), item.getQuantity());
			}
		}
		return values;
	}

	private ItemValue itemValue(ItemState item)
	{
		return item == null ? null : new ItemValue(item.id, itemName(item.id), item.quantity);
	}

	private String itemName(int id)
	{
		if (itemNames.containsKey(id))
		{
			return itemNames.get(id);
		}
		long now = System.nanoTime();
		if (nameLookupStartNanos == 0)
		{
			nameLookupStartNanos = now;
		}
		if (nameLookups >= MAX_NAME_LOOKUPS_PER_TICK
			|| now - nameLookupStartNanos >= NAME_LOOKUP_BUDGET_NANOS)
		{
			return null;
		}
		nameLookups++;
		String name = null;
		try
		{
			ItemComposition definition = client.getItemDefinition(id);
			name = definition == null ? null : definition.getName();
		}
		catch (RuntimeException ex)
		{
			log.debug("Unable to resolve RuneLite item definition {}", id, ex);
		}
		itemNames.put(id, name);
		return name;
	}

	private void reconcileMovement(List<PendingEvent> events, Player player)
	{
		WorldPoint point = player.getWorldLocation();
		Location location = new Location(point.getX(), point.getY(), point.getPlane(), point.getRegionID());
		MovementState after = new MovementState(location, client.getLocalDestinationLocation() != null, player.getAnimation());
		if (movement == null || !movement.equals(after))
		{
			events.add(new PendingEvent(EventType.MOVEMENT_CHANGED, client.getTickCount(),
				new MovementChange(movement == null ? null : movement.location,
					after.location, after.moving, after.animationId)));
		}
		movement = after;
	}

	private void reconcileInteraction(List<PendingEvent> events, Player player)
	{
		Target after = target(player.getInteracting());
		boolean same = interaction == null ? after == null : interaction.sameIdentity(after);
		if (!same)
		{
			events.add(new PendingEvent(EventType.INTERACTION_CHANGED, client.getTickCount(),
				new InteractionChange(interaction, after)));
		}
		interaction = after;
	}

	private static Target target(Actor actor)
	{
		if (actor == null)
		{
			return null;
		}
		if (actor instanceof NPC)
		{
			NPC npc = (NPC) actor;
			return new Target("npc", npc.getId(), npc.getName(), npc.getCombatLevel());
		}
		if (actor instanceof Player)
		{
			return new Target("player", null, null, actor.getCombatLevel());
		}
		return new Target("actor", null, null, null);
	}

	private Player activePlayer()
	{
		return client.getGameState() == GameState.LOGGED_IN ? client.getLocalPlayer() : null;
	}

	private EventMetadata metadata(Player player)
	{
		GameState state = client.getGameState();
		return new EventMetadata(normalizedState(state, player != null), state.name(), client.getTickCount());
	}

	private static String normalizedState(GameState state, boolean hasPlayer)
	{
		if (state == GameState.LOGGED_IN && hasPlayer)
		{
			return "active";
		}
		return isLoginScreen(state) ? "logged_out" : "loading";
	}

	private static boolean isLoginScreen(GameState state)
	{
		return state == GameState.LOGIN_SCREEN || state == GameState.LOGIN_SCREEN_AUTHENTICATOR;
	}

	private void clearBaselines(boolean clearIdentity)
	{
		dirtySkills.clear();
		skills.clear();
		inventoryDirty = false;
		equipmentDirty = false;
		inventory = null;
		equipment = null;
		movement = null;
		interaction = null;
		if (clearIdentity)
		{
			playerName = null;
			itemNames.clear();
		}
	}

	private void warnIfSlow(long started)
	{
		long elapsed = System.nanoTime() - started;
		long now = System.nanoTime();
		if (elapsed > SLOW_RECONCILIATION_NANOS && now - lastWarningNanos > WARNING_INTERVAL_NANOS)
		{
			lastWarningNanos = now;
			log.warn("RuneLite MCP event reconciliation took {} microseconds", elapsed / 1_000);
		}
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

	private static final class SkillState
	{
		private final int baseLevel;
		private final int currentLevel;
		private final int experience;

		private SkillState(int baseLevel, int currentLevel, int experience)
		{
			this.baseLevel = baseLevel;
			this.currentLevel = currentLevel;
			this.experience = experience;
		}

		@Override
		public boolean equals(Object other)
		{
			if (!(other instanceof SkillState))
			{
				return false;
			}
			SkillState value = (SkillState) other;
			return baseLevel == value.baseLevel && currentLevel == value.currentLevel && experience == value.experience;
		}

		@Override
		public int hashCode()
		{
			return Objects.hash(baseLevel, currentLevel, experience);
		}
	}

	private static final class ItemState
	{
		private final int id;
		private final int quantity;

		private ItemState(int id, int quantity)
		{
			this.id = id;
			this.quantity = quantity;
		}

		@Override
		public boolean equals(Object other)
		{
			if (!(other instanceof ItemState))
			{
				return false;
			}
			ItemState value = (ItemState) other;
			return id == value.id && quantity == value.quantity;
		}

		@Override
		public int hashCode()
		{
			return Objects.hash(id, quantity);
		}
	}

	private static final class MovementState
	{
		private final Location location;
		private final boolean moving;
		private final int animationId;

		private MovementState(Location location, boolean moving, int animationId)
		{
			this.location = location;
			this.moving = moving;
			this.animationId = animationId;
		}

		@Override
		public boolean equals(Object other)
		{
			if (!(other instanceof MovementState))
			{
				return false;
			}
			MovementState value = (MovementState) other;
			return moving == value.moving && animationId == value.animationId && location.equals(value.location);
		}

		@Override
		public int hashCode()
		{
			return Objects.hash(location, moving, animationId);
		}
	}
}
