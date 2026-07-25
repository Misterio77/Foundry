package rs.m7.runelitemcp.snapshot;

import com.google.gson.JsonObject;
import java.lang.reflect.Proxy;
import net.runelite.api.Client;
import net.runelite.api.ItemComposition;
import net.runelite.api.Quest;
import net.runelite.api.gameval.VarPlayerID;
import net.runelite.api.gameval.VarbitID;
import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

public class ProgressionSnapshotReaderTest
{
	@Test
	public void readsQuestTotalsAndBoundedFilters()
	{
		ProgressionSnapshotReader reader = new ProgressionSnapshotReader(client());
		JsonObject arguments = new JsonObject();
		arguments.addProperty("query", "dragon");
		arguments.addProperty("limit", 2);
		JsonObject quests = reader.quests(arguments);
		assertEquals(Quest.values().length, quests.getAsJsonObject("counts").get("total").getAsInt());
		assertEquals(123, quests.get("questPoints").getAsInt());
		assertEquals(2, quests.getAsJsonObject("page").getAsJsonArray("quests").size());
		assertTrue(quests.getAsJsonObject("page").get("total").getAsInt() >= 2);
	}

	@Test
	public void readsDiarySlayerAndCollectionSummaries()
	{
		ProgressionSnapshotReader reader = new ProgressionSnapshotReader(client());
		JsonObject diaries = reader.diaries(new JsonObject());
		assertEquals(12, diaries.getAsJsonArray("regions").size());
		assertEquals(48, diaries.get("totalTiers").getAsInt());
		assertTrue(diaries.get("completedTiers").getAsInt() > 0);

		JsonObject slayer = reader.slayer(new JsonObject());
		assertEquals(321, slayer.getAsJsonObject("rewards").get("points").getAsInt());
		assertEquals(55, slayer.getAsJsonObject("task").get("remaining").getAsInt());
		assertEquals("Duradel", slayer.getAsJsonObject("task").get("masterName").getAsString());

		JsonObject collection = reader.collectionLog();
		assertEquals(100, collection.getAsJsonObject("totals").get("obtained").getAsInt());
		assertEquals(500, collection.getAsJsonObject("totals").get("total").getAsInt());
		assertEquals("summary", collection.get("completeness").getAsString());
		assertEquals("current_summary", collection.get("availability").getAsString());
		assertEquals("current", collection.get("synchronization").getAsString());
	}

	private static Client client()
	{
		return (Client) Proxy.newProxyInstance(Client.class.getClassLoader(), new Class<?>[]{Client.class},
			(proxy, method, args) ->
			{
				switch (method.getName())
				{
					case "getVarpValue":
						int varp = (int) args[0];
						if (varp == VarPlayerID.QP) return 123;
						if (varp == VarPlayerID.SLAYER_TARGET) return 0;
						if (varp == VarPlayerID.SLAYER_COUNT) return 55;
						if (varp == VarPlayerID.SLAYER_COUNT_ORIGINAL) return 100;
						if (varp == VarPlayerID.COLLECTION_COUNT) return 100;
						if (varp == VarPlayerID.COLLECTION_COUNT_MAX) return 500;
						return 0;
					case "getVarbitValue":
						int varbit = (int) args[0];
						if (varbit == VarbitID.SLAYER_POINTS) return 321;
						if (varbit == VarbitID.SLAYER_MASTER) return 5;
						if (varbit == VarbitID.ARDOUGNE_EASY_REWARD) return 1;
						return 0;
					case "getItemDefinition":
						return itemDefinition((int) args[0]);
					case "getDBRowsByValue":
						return java.util.Collections.emptyList();
					default:
						return defaultValue(method.getReturnType());
				}
			});
	}

	private static ItemComposition itemDefinition(int id)
	{
		return (ItemComposition) Proxy.newProxyInstance(ItemComposition.class.getClassLoader(),
			new Class<?>[]{ItemComposition.class}, (proxy, method, args) ->
				"getName".equals(method.getName()) ? "Item " + id : defaultValue(method.getReturnType()));
	}

	private static Object defaultValue(Class<?> type)
	{
		if (!type.isPrimitive()) return null;
		if (type == boolean.class) return false;
		if (type == byte.class) return (byte) 0;
		if (type == short.class) return (short) 0;
		if (type == int.class) return 0;
		if (type == long.class) return 0L;
		if (type == float.class) return 0F;
		if (type == double.class) return 0D;
		if (type == char.class) return '\0';
		return null;
	}
}
