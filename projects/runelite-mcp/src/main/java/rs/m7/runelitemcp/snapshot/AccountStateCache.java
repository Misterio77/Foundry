package rs.m7.runelitemcp.snapshot;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Deque;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import javax.inject.Singleton;
import net.runelite.api.Client;
import net.runelite.api.GrandExchangeOffer;
import net.runelite.api.Item;
import net.runelite.api.ItemComposition;
import net.runelite.api.ItemContainer;
import net.runelite.api.gameval.InventoryID;
import net.runelite.client.game.ItemManager;

@Singleton
public final class AccountStateCache
{
	private static final int MAX_CONTAINER_SLOTS = 1_000;
	private static final long METADATA_STALE_MILLIS = 5 * 60 * 1_000L;
	private static final int[] CACHED_IDS = {
		InventoryID.INV,
		InventoryID.WORN,
		InventoryID.BANK,
		InventoryID.SEED_VAULT,
		InventoryID.LOOTING_BAG,
		InventoryID.SEED_BOX,
		InventoryID.TACKLE_BOX,
		InventoryID.FORESTRY_KIT,
		InventoryID.HUNTSMANS_KIT
	};

	private final Map<Integer, ContainerSnapshot> containers = new HashMap<>();
	private final Map<Integer, ItemMetadata> metadata = new HashMap<>();
	private final Deque<Integer> pendingMetadata = new ArrayDeque<>();
	private final Set<Integer> pendingMetadataSet = new HashSet<>();
	private List<OfferSnapshot> offers = Collections.emptyList();
	private ContainerSnapshot runePouch;
	private int offersTick;
	private long offersObservedAt;
	private long generation = 1;
	private String playerName;

	public synchronized void observe(int containerId, ItemContainer container, int tick)
	{
		if (!isCached(containerId) || container == null)
		{
			return;
		}
		Item[] source = container.getItems();
		List<ItemStack> items = new ArrayList<>();
		if (source != null)
		{
			for (int slot = 0; slot < Math.min(source.length, MAX_CONTAINER_SLOTS); slot++)
			{
				Item item = source[slot];
				if (item != null && item.getId() > 0 && item.getQuantity() > 0)
				{
					items.add(new ItemStack(slot, item.getId(), item.getQuantity()));
					queueMetadata(item.getId());
				}
			}
		}
		containers.put(containerId, new ContainerSnapshot(tick, System.currentTimeMillis(), items));
	}

	public synchronized ContainerSnapshot get(int containerId)
	{
		return containers.get(containerId);
	}

	public synchronized void observeOffers(GrandExchangeOffer[] source, int tick)
	{
		if (source == null)
		{
			return;
		}
		List<OfferSnapshot> values = new ArrayList<>();
		for (int slot = 0; slot < Math.min(8, source.length); slot++)
		{
			GrandExchangeOffer offer = source[slot];
			if (offer != null && offer.getState() != null && !"EMPTY".equals(offer.getState().name()))
			{
				values.add(new OfferSnapshot(slot, offer.getState().name(), offer.getItemId(), offer.getPrice(),
					offer.getTotalQuantity(), offer.getQuantitySold(), offer.getSpent()));
				queueMetadata(offer.getItemId());
			}
		}
		offers = Collections.unmodifiableList(values);
		offersTick = tick;
		offersObservedAt = System.currentTimeMillis();
	}

	public synchronized OffersSnapshot getOffers()
	{
		return offersObservedAt == 0 ? null : new OffersSnapshot(offersTick, offersObservedAt, offers);
	}

	public synchronized void observeRunePouch(int[] itemIds, int[] quantities, int tick)
	{
		List<ItemStack> values = new ArrayList<>();
		for (int slot = 0; slot < Math.min(itemIds.length, quantities.length); slot++)
		{
			if (itemIds[slot] > 0 && quantities[slot] > 0)
			{
				values.add(new ItemStack(slot, itemIds[slot], quantities[slot]));
				queueMetadata(itemIds[slot]);
			}
		}
		runePouch = new ContainerSnapshot(tick, System.currentTimeMillis(), values);
	}

	public synchronized ContainerSnapshot getRunePouch()
	{
		return runePouch;
	}

	public void enrichMetadata(Client client, ItemManager itemManager, int limit)
	{
		for (int count = 0; count < limit; count++)
		{
			Integer id;
			synchronized (this)
			{
				id = pendingMetadata.pollFirst();
				if (id == null)
				{
					return;
				}
				pendingMetadataSet.remove(id);
			}
			ItemComposition definition = client.getItemDefinition(id);
			String name = definition == null ? null : definition.getName();
			int price = itemManager == null ? 0 : Math.max(0, itemManager.getItemPrice(id));
			synchronized (this)
			{
				metadata.put(id, new ItemMetadata(name, price, System.currentTimeMillis()));
			}
		}
	}

	public synchronized ItemMetadata getMetadata(int id)
	{
		ItemMetadata value = metadata.get(id);
		if (value == null || System.currentTimeMillis() - value.getObservedAt() > METADATA_STALE_MILLIS)
		{
			metadata.remove(id);
			queueMetadata(id);
		}
		return value;
	}

	public synchronized int getPendingMetadataCount()
	{
		return pendingMetadata.size();
	}

	public synchronized long getGeneration()
	{
		return generation;
	}

	public synchronized void bindPlayer(String name)
	{
		if (name == null)
		{
			return;
		}
		if (playerName != null && !playerName.equals(name))
		{
			clearState();
		}
		playerName = name;
	}

	public synchronized void clear()
	{
		clearState();
		playerName = null;
	}

	private void clearState()
	{
		generation = generation == Long.MAX_VALUE ? 1 : generation + 1;
		containers.clear();
		metadata.clear();
		pendingMetadata.clear();
		pendingMetadataSet.clear();
		offers = Collections.emptyList();
		runePouch = null;
		offersTick = 0;
		offersObservedAt = 0;
	}

	private void queueMetadata(int id)
	{
		if (id > 0 && !metadata.containsKey(id) && pendingMetadataSet.add(id))
		{
			pendingMetadata.addLast(id);
		}
	}

	private static boolean isCached(int id)
	{
		for (int cached : CACHED_IDS)
		{
			if (cached == id)
			{
				return true;
			}
		}
		return false;
	}

	public static final class ItemMetadata
	{
		private final String name;
		private final int marketPrice;
		private final long observedAt;

		private ItemMetadata(String name, int marketPrice, long observedAt)
		{
			this.name = name;
			this.marketPrice = marketPrice;
			this.observedAt = observedAt;
		}

		public String getName() { return name; }
		public int getMarketPrice() { return marketPrice; }
		public long getObservedAt() { return observedAt; }
	}

	public static final class OffersSnapshot
	{
		private final int tick;
		private final long observedAt;
		private final List<OfferSnapshot> offers;

		private OffersSnapshot(int tick, long observedAt, List<OfferSnapshot> offers)
		{
			this.tick = tick;
			this.observedAt = observedAt;
			this.offers = Collections.unmodifiableList(new ArrayList<>(offers));
		}

		public int getTick() { return tick; }
		public long getObservedAt() { return observedAt; }
		public List<OfferSnapshot> getOffers() { return offers; }
	}

	public static final class OfferSnapshot
	{
		private final int slot;
		private final String state;
		private final int itemId;
		private final int price;
		private final int totalQuantity;
		private final int completedQuantity;
		private final int spent;

		private OfferSnapshot(int slot, String state, int itemId, int price,
			int totalQuantity, int completedQuantity, int spent)
		{
			this.slot = slot;
			this.state = state;
			this.itemId = itemId;
			this.price = price;
			this.totalQuantity = totalQuantity;
			this.completedQuantity = completedQuantity;
			this.spent = spent;
		}

		public int getSlot() { return slot; }
		public String getState() { return state; }
		public int getItemId() { return itemId; }
		public int getPrice() { return price; }
		public int getTotalQuantity() { return totalQuantity; }
		public int getCompletedQuantity() { return completedQuantity; }
		public int getSpent() { return spent; }
	}

	public static final class ContainerSnapshot
	{
		private final int tick;
		private final long observedAt;
		private final List<ItemStack> items;

		private ContainerSnapshot(int tick, long observedAt, List<ItemStack> items)
		{
			this.tick = tick;
			this.observedAt = observedAt;
			this.items = Collections.unmodifiableList(new ArrayList<>(items));
		}

		public int getTick()
		{
			return tick;
		}

		public long getObservedAt()
		{
			return observedAt;
		}

		public List<ItemStack> getItems()
		{
			return items;
		}
	}

	public static final class ItemStack
	{
		private final int slot;
		private final int id;
		private final int quantity;

		private ItemStack(int slot, int id, int quantity)
		{
			this.slot = slot;
			this.id = id;
			this.quantity = quantity;
		}

		public int getSlot()
		{
			return slot;
		}

		public int getId()
		{
			return id;
		}

		public int getQuantity()
		{
			return quantity;
		}
	}
}
