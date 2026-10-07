package rs.m7.runelitequery.snapshot;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.lang.reflect.Proxy;
import net.runelite.api.Client;
import net.runelite.api.GrandExchangeOffer;
import net.runelite.api.GrandExchangeOfferState;
import net.runelite.api.Item;
import net.runelite.api.ItemComposition;
import net.runelite.api.ItemContainer;
import net.runelite.api.gameval.InventoryID;
import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

public class AccountStateSnapshotReaderTest
{
	@Test
	public void returnsCachedFilteredBankWithFreshnessMetadata()
	{
		AccountStateCache cache = new AccountStateCache();
		cache.observe(InventoryID.BANK, container(new Item[]{new Item(995, 1000), new Item(946, 1)}), 77);
		AccountStateSnapshotReader reader = new AccountStateSnapshotReader(client(), null, cache);
		JsonObject arguments = new JsonObject();
		JsonArray containers = new JsonArray();
		containers.add("bank");
		arguments.add("containers", containers);
		arguments.addProperty("itemId", 995);
		arguments.addProperty("limit", 10);

		JsonObject bank = reader.storedItems(arguments).getAsJsonObject("bank");
		assertEquals("observed", bank.get("availability").getAsString());
		assertEquals(77, bank.get("observedTick").getAsInt());
		assertEquals(2, bank.get("totalStacks").getAsInt());
		assertEquals(1, bank.getAsJsonObject("page").getAsJsonArray("items").size());
		assertEquals(995, bank.getAsJsonObject("page").getAsJsonArray("items")
			.get(0).getAsJsonObject().get("id").getAsInt());
	}

	@Test
	public void preservesGrandExchangePricesAndSpentAboveIntegerRange()
	{
		long price = 3_000_000_000L;
		long spent = 6_000_000_000L;
		GrandExchangeOffer offer = (GrandExchangeOffer) Proxy.newProxyInstance(
			GrandExchangeOffer.class.getClassLoader(), new Class<?>[]{GrandExchangeOffer.class},
			(proxy, method, args) ->
			{
				switch (method.getName())
				{
					case "getState": return GrandExchangeOfferState.SELLING;
					case "getItemId": return 946;
					case "getPrice": return price;
					case "getSpent": return spent;
					case "getTotalQuantity": return 3;
					case "getQuantitySold": return 2;
					default: throw new AssertionError("Unexpected offer method: " + method.getName());
				}
			});
		AccountStateCache cache = new AccountStateCache();
		cache.observeOffers(new GrandExchangeOffer[]{offer}, 77);
		assertEquals(price, cache.getOffers().getOffers().get(0).getPrice());
		assertEquals(spent, cache.getOffers().getOffers().get(0).getSpent());

		JsonObject result = new AccountStateSnapshotReader(client(), null, cache).grandExchange();
		JsonObject value = result.getAsJsonArray("offers").get(0).getAsJsonObject();
		assertEquals(price, value.get("listedPrice").getAsLong());
		assertEquals(spent, value.get("spent").getAsLong());
		assertEquals(price * 3, value.get("listedValue").getAsLong());
		assertEquals(spent, value.get("accountValueEstimate").getAsLong());
	}

	@Test
	public void marksWealthPartialUntilBankHasBeenObserved()
	{
		AccountStateSnapshotReader reader = new AccountStateSnapshotReader(client(), null, new AccountStateCache());
		JsonObject wealth = reader.wealth();
		assertEquals(0, wealth.get("knownTotalEstimate").getAsLong());
		assertTrue(wealth.get("partial").getAsBoolean());
		assertEquals("unavailable", wealth.get("priceSource").getAsString());
	}

	private static Client client()
	{
		return (Client) Proxy.newProxyInstance(Client.class.getClassLoader(), new Class<?>[]{Client.class},
			(proxy, method, args) ->
			{
				switch (method.getName())
				{
					case "getItemContainer": return null;
					case "getGrandExchangeOffers": return null;
					case "getTickCount": return 80;
					case "getItemDefinition": return itemDefinition((int) args[0]);
					case "getVarbitValue": return 0;
					case "getEnum": return null;
					default: return defaultValue(method.getReturnType());
				}
			});
	}

	private static ItemComposition itemDefinition(int id)
	{
		return (ItemComposition) Proxy.newProxyInstance(ItemComposition.class.getClassLoader(),
			new Class<?>[]{ItemComposition.class}, (proxy, method, args) ->
			{
				if ("getName".equals(method.getName())) return id == 995 ? "Coins" : "Knife";
				return defaultValue(method.getReturnType());
			});
	}

	private static ItemContainer container(Item[] items)
	{
		return (ItemContainer) Proxy.newProxyInstance(ItemContainer.class.getClassLoader(),
			new Class<?>[]{ItemContainer.class}, (proxy, method, args) ->
				"getItems".equals(method.getName()) ? items : defaultValue(method.getReturnType()));
	}

	private static Object defaultValue(Class<?> type)
	{
		if (!type.isPrimitive()) return null;
		if (type == boolean.class) return false;
		if (type == int.class) return 0;
		if (type == long.class) return 0L;
		if (type == double.class) return 0D;
		if (type == float.class) return 0F;
		if (type == short.class) return (short) 0;
		if (type == byte.class) return (byte) 0;
		if (type == char.class) return '\0';
		return null;
	}
}
