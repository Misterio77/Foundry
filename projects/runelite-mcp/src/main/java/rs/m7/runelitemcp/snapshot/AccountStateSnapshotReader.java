package rs.m7.runelitemcp.snapshot;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.HashSet;
import net.runelite.api.Client;
import net.runelite.api.EnumComposition;
import net.runelite.api.EnumID;
import net.runelite.api.gameval.InventoryID;
import net.runelite.api.gameval.VarbitID;
import net.runelite.client.game.ItemManager;
import rs.m7.runelitemcp.snapshot.AccountStateCache.ContainerSnapshot;
import rs.m7.runelitemcp.snapshot.AccountStateCache.ItemStack;
import rs.m7.runelitemcp.snapshot.AccountStateCache.OfferSnapshot;
import rs.m7.runelitemcp.snapshot.AccountStateCache.OffersSnapshot;

final class AccountStateSnapshotReader
{
	private static final long PRICE_CACHE_MILLIS = 5 * 60 * 1_000L;
	private static final long CONTAINER_STALE_MILLIS = 60 * 60 * 1_000L;
	private static final Map<String, Integer> CONTAINERS;
	private static final int[] RUNE_TYPES = {
		VarbitID.RUNE_POUCH_TYPE_1, VarbitID.RUNE_POUCH_TYPE_2, VarbitID.RUNE_POUCH_TYPE_3,
		VarbitID.RUNE_POUCH_TYPE_4, VarbitID.RUNE_POUCH_TYPE_5, VarbitID.RUNE_POUCH_TYPE_6
	};
	private static final int[] RUNE_QUANTITIES = {
		VarbitID.RUNE_POUCH_QUANTITY_1, VarbitID.RUNE_POUCH_QUANTITY_2, VarbitID.RUNE_POUCH_QUANTITY_3,
		VarbitID.RUNE_POUCH_QUANTITY_4, VarbitID.RUNE_POUCH_QUANTITY_5, VarbitID.RUNE_POUCH_QUANTITY_6
	};

	static
	{
		Map<String, Integer> containers = new LinkedHashMap<>();
		containers.put("bank", InventoryID.BANK);
		containers.put("seed_vault", InventoryID.SEED_VAULT);
		containers.put("looting_bag", InventoryID.LOOTING_BAG);
		containers.put("seed_box", InventoryID.SEED_BOX);
		containers.put("tackle_box", InventoryID.TACKLE_BOX);
		containers.put("forestry_kit", InventoryID.FORESTRY_KIT);
		containers.put("huntsmans_kit", InventoryID.HUNTSMANS_KIT);
		CONTAINERS = Collections.unmodifiableMap(containers);
	}

	private final Client client;
	private final ItemManager itemManager;
	private final boolean pricesAvailable;
	private final AccountStateCache cache;

	AccountStateSnapshotReader(Client client, ItemManager itemManager, AccountStateCache cache)
	{
		this.client = client;
		this.itemManager = itemManager;
		this.pricesAvailable = itemManager != null;
		this.cache = cache;
	}

	long generation()
	{
		return cache.getGeneration();
	}

	void observeClientState(SnapshotType type)
	{
		if (client.getLocalPlayer() != null && client.getLocalPlayer().getName() != null)
		{
			cache.bindPlayer(client.getLocalPlayer().getName());
		}
		else
		{
			cache.clear();
		}
		if (type == SnapshotType.GRAND_EXCHANGE || type == SnapshotType.ACCOUNT_WEALTH)
		{
			cache.observeOffers(client.getGrandExchangeOffers(), client.getTickCount());
		}
		if (type == SnapshotType.ACCOUNT_WEALTH)
		{
			cache.observe(InventoryID.INV, client.getItemContainer(InventoryID.INV), client.getTickCount());
			cache.observe(InventoryID.WORN, client.getItemContainer(InventoryID.WORN), client.getTickCount());
		}
		if (type == SnapshotType.STORED_ITEMS || type == SnapshotType.ACCOUNT_WEALTH)
		{
			observeRunePouch();
		}
		cache.enrichMetadata(client, itemManager, 8);
	}

	private void observeRunePouch()
	{
		EnumComposition runeTypes = client.getEnum(EnumID.RUNEPOUCH_RUNE);
		if (runeTypes == null)
		{
			return;
		}
		int[] itemIds = new int[RUNE_TYPES.length];
		int[] quantities = new int[RUNE_TYPES.length];
		for (int slot = 0; slot < RUNE_TYPES.length; slot++)
		{
			itemIds[slot] = runeTypes.getIntValue(client.getVarbitValue(RUNE_TYPES[slot]));
			quantities[slot] = client.getVarbitValue(RUNE_QUANTITIES[slot]);
		}
		cache.observeRunePouch(itemIds, quantities, client.getTickCount());
	}

	JsonObject grandExchange()
	{
		OffersSnapshot source = cache.getOffers();
		JsonObject result = new JsonObject();
		result.addProperty("availability", source == null ? "unavailable" : "observed");
		if (source == null)
		{
			result.add("observedTick", JsonNull.INSTANCE);
			result.add("observedAt", JsonNull.INSTANCE);
		}
		else
		{
			result.addProperty("observedTick", source.getTick());
			result.addProperty("observedAt", source.getObservedAt());
		}
		JsonArray offers = new JsonArray();
		long listedValue = 0;
		long accountValue = 0;
		if (source != null)
		{
			for (OfferSnapshot offer : source.getOffers())
			{
				int id = offer.getItemId();
				int marketPrice = metadata(id).marketPrice;
				int total = offer.getTotalQuantity();
				int completed = offer.getCompletedQuantity();
				int remaining = Math.max(0, total - completed);
				long offerListed = (long) offer.getPrice() * total;
				long offerValue = offerValue(offer.getState(), marketPrice, offer.getPrice(),
					total, completed, remaining, offer.getSpent());
				JsonObject value = new JsonObject();
				value.addProperty("slot", offer.getSlot());
				value.addProperty("state", offer.getState().toLowerCase(Locale.ROOT));
				value.addProperty("itemId", id);
				addNullable(value, "name", metadata(id).name);
				value.addProperty("listedPrice", offer.getPrice());
				value.addProperty("marketPriceEstimate", marketPrice);
				value.addProperty("totalQuantity", total);
				value.addProperty("completedQuantity", completed);
				value.addProperty("remainingQuantity", remaining);
				value.addProperty("spent", offer.getSpent());
				value.addProperty("listedValue", offerListed);
				value.addProperty("accountValueEstimate", offerValue);
				offers.add(value);
				listedValue += offerListed;
				accountValue += offerValue;
			}
		}
		result.addProperty("activeOffers", offers.size());
		result.addProperty("listedValue", listedValue);
		result.addProperty("accountValueEstimate", accountValue);
		result.addProperty("priceSource", pricesAvailable ? "runelite_cache" : "unavailable");
		result.addProperty("priceMaximumAgeSeconds", pricesAvailable ? PRICE_CACHE_MILLIS / 1_000 : 0);
		result.addProperty("upstreamPriceAgeUnknown", pricesAvailable);
		result.addProperty("metadataComplete", cache.getPendingMetadataCount() == 0);
		result.add("offers", offers);
		return result;
	}

	JsonObject storedItems(JsonObject arguments)
	{
		Set<String> requested = strings(arguments, "containers");
		String query = string(arguments, "query");
		Integer itemId = optionalInteger(arguments, "itemId");
		int offset = integer(arguments, "offset", 0);
		int limit = integer(arguments, "limit", 50);
		JsonObject result = new JsonObject();
		for (Map.Entry<String, Integer> definition : CONTAINERS.entrySet())
		{
			if (!requested.isEmpty() && !requested.contains(definition.getKey()))
			{
				continue;
			}
			result.add(definition.getKey(), storedContainer(definition.getValue(), query, itemId, offset, limit));
		}
		if (requested.isEmpty() || requested.contains("rune_pouch"))
		{
			result.add("rune_pouch", runePouch(query, itemId, offset, limit));
		}
		return result;
	}

	JsonObject wealth()
	{
		JsonObject result = new JsonObject();
		JsonObject components = new JsonObject();
		long known = 0;
		boolean partial = false;
		for (Map.Entry<String, Integer> entry : CONTAINERS.entrySet())
		{
			ContainerSnapshot snapshot = cache.get(entry.getValue());
			long value = containerValue(snapshot);
			components.add(entry.getKey(), cachedWealthComponent(snapshot, value));
			known += value;
			partial |= snapshot == null || stale(snapshot);
		}
		ContainerSnapshot inventorySnapshot = cache.get(InventoryID.INV);
		ContainerSnapshot equipmentSnapshot = cache.get(InventoryID.WORN);
		long inventory = containerValue(inventorySnapshot);
		long equipment = containerValue(equipmentSnapshot);
		components.add("inventory", cachedWealthComponent(inventorySnapshot, inventory));
		components.add("equipment", cachedWealthComponent(equipmentSnapshot, equipment));
		known += inventory + equipment;
		partial |= inventorySnapshot == null || equipmentSnapshot == null;
		JsonObject runePouch = runePouch(null, null, 0, 6);
		long runePouchValue = runePouch.get("totalValueEstimate").getAsLong();
		components.add("rune_pouch", cachedWealthComponent(cache.getRunePouch(), runePouchValue));
		known += runePouchValue;
		JsonObject ge = grandExchange();
		long geValue = ge.get("accountValueEstimate").getAsLong();
		String geAvailability = ge.get("availability").getAsString();
		components.add("grandExchange", wealthComponent(geAvailability, geValue));
		known += geValue;
		partial |= !"observed".equals(geAvailability);
		result.addProperty("knownTotalEstimate", known);
		result.addProperty("priceSource", pricesAvailable ? "runelite_cache" : "unavailable");
		result.addProperty("priceMaximumAgeSeconds", pricesAvailable ? PRICE_CACHE_MILLIS / 1_000 : 0);
		result.addProperty("upstreamPriceAgeUnknown", pricesAvailable);
		result.addProperty("pricedTradeableItemsOnly", true);
		result.addProperty("metadataComplete", cache.getPendingMetadataCount() == 0);
		result.addProperty("partial", partial || !pricesAvailable || cache.getPendingMetadataCount() > 0);
		result.add("components", components);
		return result;
	}

	private JsonObject storedContainer(int containerId, String query, Integer itemId, int offset, int limit)
	{
		ContainerSnapshot snapshot = cache.get(containerId);
		JsonObject result = new JsonObject();
		if (snapshot == null)
		{
			result.addProperty("availability", "unavailable");
			result.add("observedTick", JsonNull.INSTANCE);
			result.add("observedAt", JsonNull.INSTANCE);
			result.addProperty("totalStacks", 0);
			result.addProperty("totalQuantity", 0);
			result.addProperty("totalValueEstimate", 0);
			result.add("page", itemPage(Collections.emptyList(), offset, limit));
			return result;
		}
		result.addProperty("availability", stale(snapshot) ? "stale" : "observed");
		result.addProperty("observedTick", snapshot.getTick());
		result.addProperty("observedAt", snapshot.getObservedAt());
		List<JsonObject> matching = new ArrayList<>();
		long quantity = 0;
		long value = 0;
		for (ItemStack stack : snapshot.getItems())
		{
			ItemMetadata metadata = metadata(stack.getId());
			quantity += stack.getQuantity();
			value += (long) metadata.marketPrice * stack.getQuantity();
			if (itemId != null && itemId != stack.getId()
				|| query != null && !contains(metadata.name, query))
			{
				continue;
			}
			matching.add(item(stack, metadata));
		}
		result.addProperty("totalStacks", snapshot.getItems().size());
		result.addProperty("totalQuantity", quantity);
		result.addProperty("totalValueEstimate", value);
		result.addProperty("priceSource", pricesAvailable ? "runelite_cache" : "unavailable");
		result.addProperty("priceMaximumAgeSeconds", pricesAvailable ? PRICE_CACHE_MILLIS / 1_000 : 0);
		result.addProperty("metadataComplete", cache.getPendingMetadataCount() == 0);
		result.add("page", itemPage(matching, offset, limit));
		return result;
	}

	private JsonObject runePouch(String query, Integer itemId, int offset, int limit)
	{
		List<JsonObject> matching = new ArrayList<>();
		long value = 0;
		long quantity = 0;
		ContainerSnapshot snapshot = cache.getRunePouch();
		if (snapshot != null)
		{
			for (ItemStack stack : snapshot.getItems())
			{
				ItemMetadata metadata = metadata(stack.getId());
				quantity += stack.getQuantity();
				value += (long) metadata.marketPrice * stack.getQuantity();
				if (itemId != null && itemId != stack.getId()
					|| query != null && !contains(metadata.name, query))
				{
					continue;
				}
				matching.add(item(stack, metadata));
			}
		}
		JsonObject result = new JsonObject();
		result.addProperty("availability", snapshot == null ? "unavailable" : "observed");
		if (snapshot == null)
		{
			result.add("observedTick", JsonNull.INSTANCE);
			result.add("observedAt", JsonNull.INSTANCE);
		}
		else
		{
			result.addProperty("observedTick", snapshot.getTick());
			result.addProperty("observedAt", snapshot.getObservedAt());
		}
		result.addProperty("totalStacks", snapshot == null ? 0 : snapshot.getItems().size());
		result.addProperty("totalQuantity", quantity);
		result.addProperty("totalValueEstimate", value);
		result.addProperty("priceSource", pricesAvailable ? "runelite_cache" : "unavailable");
		result.addProperty("priceMaximumAgeSeconds", pricesAvailable ? PRICE_CACHE_MILLIS / 1_000 : 0);
		result.addProperty("metadataComplete", cache.getPendingMetadataCount() == 0);
		result.add("page", itemPage(matching, offset, limit));
		return result;
	}

	private long containerValue(ContainerSnapshot snapshot)
	{
		if (snapshot == null)
		{
			return 0;
		}
		long value = 0;
		for (ItemStack item : snapshot.getItems())
		{
			value += (long) metadata(item.getId()).marketPrice * item.getQuantity();
		}
		return value;
	}

	private ItemMetadata metadata(int id)
	{
		AccountStateCache.ItemMetadata cached = cache.getMetadata(id);
		return cached == null ? new ItemMetadata(null, 0)
			: new ItemMetadata(cached.getName(), cached.getMarketPrice());
	}

	private static JsonObject item(ItemStack stack, ItemMetadata metadata)
	{
		JsonObject item = new JsonObject();
		item.addProperty("slot", stack.getSlot());
		item.addProperty("id", stack.getId());
		addNullable(item, "name", metadata.name);
		item.addProperty("quantity", stack.getQuantity());
		item.addProperty("marketPriceEstimate", metadata.marketPrice);
		item.addProperty("valueEstimate", (long) metadata.marketPrice * stack.getQuantity());
		return item;
	}

	private static JsonObject itemPage(List<JsonObject> values, int offset, int limit)
	{
		int from = Math.min(offset, values.size());
		int to = from + Math.min(limit, values.size() - from);
		JsonArray items = new JsonArray();
		for (int index = from; index < to; index++)
		{
			items.add(values.get(index));
		}
		JsonObject page = new JsonObject();
		page.addProperty("offset", offset);
		page.addProperty("limit", limit);
		page.addProperty("matchingStacks", values.size());
		page.addProperty("hasMore", to < values.size());
		page.add("items", items);
		return page;
	}

	private static JsonObject cachedWealthComponent(ContainerSnapshot snapshot, long value)
	{
		JsonObject component = wealthComponent(snapshot == null ? "unavailable"
			: stale(snapshot) ? "stale" : "observed", value);
		if (snapshot == null)
		{
			component.add("observedTick", JsonNull.INSTANCE);
			component.add("observedAt", JsonNull.INSTANCE);
		}
		else
		{
			component.addProperty("observedTick", snapshot.getTick());
			component.addProperty("observedAt", snapshot.getObservedAt());
		}
		return component;
	}

	private static boolean stale(ContainerSnapshot snapshot)
	{
		return System.currentTimeMillis() - snapshot.getObservedAt() > CONTAINER_STALE_MILLIS;
	}

	private static JsonObject wealthComponent(String availability, long value)
	{
		JsonObject component = new JsonObject();
		component.addProperty("availability", availability);
		component.addProperty("valueEstimate", value);
		return component;
	}

	private static long offerValue(String state, int marketPrice, int listedPrice,
		int total, int completed, int remaining, int spent)
	{
		if (state.contains("SELL"))
		{
			return (long) spent + (long) marketPrice * remaining;
		}
		if (state.contains("BUY"))
		{
			return (long) marketPrice * completed + (long) listedPrice * remaining;
		}
		return (long) marketPrice * total;
	}

	private static Set<String> strings(JsonObject arguments, String name)
	{
		if (arguments == null || !arguments.has(name))
		{
			return Collections.emptySet();
		}
		Set<String> values = new HashSet<>();
		for (JsonElement value : arguments.getAsJsonArray(name))
		{
			values.add(value.getAsString());
		}
		return values;
	}

	private static String string(JsonObject arguments, String name)
	{
		return arguments == null || !arguments.has(name) ? null
			: arguments.get(name).getAsString().toLowerCase(Locale.ROOT);
	}

	private static int integer(JsonObject arguments, String name, int fallback)
	{
		return arguments == null || !arguments.has(name) ? fallback : arguments.get(name).getAsInt();
	}

	private static Integer optionalInteger(JsonObject arguments, String name)
	{
		return arguments == null || !arguments.has(name) ? null : arguments.get(name).getAsInt();
	}

	private static boolean contains(String value, String query)
	{
		return value != null && value.toLowerCase(Locale.ROOT).contains(query);
	}

	private static void addNullable(JsonObject object, String name, String value)
	{
		if (value == null)
		{
			object.add(name, JsonNull.INSTANCE);
		}
		else
		{
			object.addProperty(name, value);
		}
	}

	private static final class ItemMetadata
	{
		private final String name;
		private final int marketPrice;

		private ItemMetadata(String name, int marketPrice)
		{
			this.name = name;
			this.marketPrice = marketPrice;
		}
	}
}
