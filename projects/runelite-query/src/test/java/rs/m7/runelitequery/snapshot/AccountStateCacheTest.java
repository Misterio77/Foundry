package rs.m7.runelitequery.snapshot;

import java.lang.reflect.Proxy;
import net.runelite.api.Item;
import net.runelite.api.ItemContainer;
import net.runelite.api.gameval.InventoryID;
import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

public class AccountStateCacheTest
{
	@Test
	public void retainsBoundedDefensiveContainerCopiesAndClearsAtAccountBoundary()
	{
		AccountStateCache cache = new AccountStateCache();
		Item[] items = {new Item(995, 123), null, new Item(946, 1)};
		cache.observe(InventoryID.BANK, container(items), 42);
		items[0] = new Item(1, 1);

		AccountStateCache.ContainerSnapshot snapshot = cache.get(InventoryID.BANK);
		assertEquals(42, snapshot.getTick());
		assertEquals(2, snapshot.getItems().size());
		assertEquals(995, snapshot.getItems().get(0).getId());
		assertEquals(123, snapshot.getItems().get(0).getQuantity());

		cache.observe(InventoryID.INV, container(items), 43);
		assertEquals(1, cache.get(InventoryID.INV).getItems().get(0).getId());
		cache.bindPlayer("first");
		long generation = cache.getGeneration();
		cache.bindPlayer(null);
		assertEquals(995, cache.get(InventoryID.BANK).getItems().get(0).getId());
		cache.bindPlayer("second");
		assertEquals(generation + 1, cache.getGeneration());
		assertNull(cache.get(InventoryID.BANK));
		cache.clear();
		assertNull(cache.get(InventoryID.BANK));
	}

	private static ItemContainer container(Item[] items)
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
}
