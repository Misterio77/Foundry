package rs.m7.runelitequery.snapshot;

import com.google.gson.JsonObject;
import java.lang.reflect.Proxy;
import net.runelite.api.Client;
import net.runelite.api.DecorativeObject;
import net.runelite.api.GameObject;
import net.runelite.api.ObjectComposition;
import net.runelite.api.Player;
import net.runelite.api.Scene;
import net.runelite.api.Tile;
import net.runelite.api.TileObject;
import net.runelite.api.coords.WorldPoint;
import net.runelite.client.plugins.poh.PohIcons;
import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class PohSnapshotReaderTest
{
	@Test
	public void reportsNoLayoutOutsideLoadedHouse()
	{
		JsonObject poh = new PohSnapshotReader(client(new WorldPoint(3169, 3491, 0), null)).read();
		assertEquals("not_in_house", poh.get("availability").getAsString());
		assertEquals("unknown", poh.get("ownership").getAsString());
		assertEquals(0, poh.getAsJsonArray("features").size());
	}

	@Test
	public void reportsUnavailableWhenHouseSceneIsMissing()
	{
		JsonObject poh = new PohSnapshotReader(client(new WorldPoint(1880, 7050, 0), null)).read();
		assertEquals("unavailable", poh.get("availability").getAsString());
	}

	@Test
	public void provesSelfOwnershipFromBuildingMode()
	{
		Tile[][][] tiles = new Tile[4][1][1];
		JsonObject poh = new PohSnapshotReader(client(new WorldPoint(1880, 7050, 0), scene(tiles), 1)).read();
		assertEquals("self", poh.get("ownership").getAsString());
		assertEquals("building_mode", poh.get("ownershipEvidence").getAsString());
	}

	@Test
	public void retainsOnlyConfirmedSelfHouseAfterLeaving()
	{
		WorldPoint[] location = {new WorldPoint(1880, 7050, 0)};
		Tile[][][] tiles = new Tile[4][1][1];
		PohSnapshotReader reader = new PohSnapshotReader(client(location, scene(tiles), 1));
		assertEquals("self", reader.read().get("ownership").getAsString());
		reader.sceneChanged();
		location[0] = new WorldPoint(3169, 3491, 0);
		JsonObject observed = reader.read();
		assertEquals("observed", observed.get("availability").getAsString());
		assertEquals("last_observed_self_house", observed.get("scope").getAsString());
		reader.clearAccount();
		assertEquals("not_in_house", reader.read().get("availability").getAsString());
	}

	@Test
	public void confirmsSelfHouseOnlyWhenArmedActionLoadsIntoPoh()
	{
		WorldPoint[] location = {new WorldPoint(3169, 3491, 0)};
		PohSnapshotReader reader = new PohSnapshotReader(client(location, scene(new Tile[4][1][1]), 0));
		reader.observeSelfEntryAction("teleport_to_house_spell");
		reader.sceneChanged();
		location[0] = new WorldPoint(1880, 7050, 0);
		reader.observationsComplete();
		reader.refreshConfirmedSelfObservation();
		reader.sceneChanged();
		location[0] = new WorldPoint(3169, 3491, 0);
		JsonObject observed = reader.read();
		assertEquals("observed", observed.get("availability").getAsString());
		assertEquals("teleport_to_house_spell", observed.get("ownershipEvidence").getAsString());
	}

	@Test
	public void doesNotConfirmArmedActionWithoutLoadingTransition()
	{
		WorldPoint[] location = {new WorldPoint(1880, 7050, 0)};
		PohSnapshotReader reader = new PohSnapshotReader(client(location, scene(new Tile[4][1][1]), 0));
		reader.observeSelfEntryAction("teleport_to_house_spell");
		reader.observationsComplete();
		assertEquals("unknown", reader.read().get("ownership").getAsString());
	}

	@Test
	public void reusesRuneLitePohFeaturesAndDeduplicatesSceneObjects()
	{
		int portalId = PohIcons.VARROCK.getIds()[0];
		int poolId = PohIcons.POOLS.getIds()[0];
		GameObject portal = object(GameObject.class, portalId, new WorldPoint(1880, 7050, 0));
		DecorativeObject pool = object(DecorativeObject.class, poolId, new WorldPoint(1881, 7050, 0));
		Tile first = tile(portal, pool);
		Tile duplicate = tile(portal, null);
		Tile[][][] tiles = new Tile[4][2][2];
		tiles[0][0][0] = first;
		tiles[0][1][0] = duplicate;

		JsonObject poh = new PohSnapshotReader(client(new WorldPoint(1880, 7050, 0), scene(tiles))).read();
		assertEquals("current", poh.get("availability").getAsString());
		assertEquals("currently_loaded_house", poh.get("scope").getAsString());
		assertEquals(2, poh.get("recognizedFeatureCount").getAsInt());
		assertEquals(1, poh.getAsJsonObject("featureCounts").get("pool").getAsInt());
		assertEquals(1, poh.getAsJsonObject("featureCounts").get("varrock").getAsInt());
		assertFalse(poh.get("truncated").getAsBoolean());
	}

	@Test
	public void maintainsSceneFeaturesFromRuneLiteObjectEvents()
	{
		int poolId = PohIcons.POOLS.getIds()[0];
		GameObject pool = object(GameObject.class, poolId, new WorldPoint(1880, 7050, 0));
		PohSnapshotReader reader = new PohSnapshotReader(client(new WorldPoint(1880, 7050, 0),
			scene(new Tile[4][1][1])));
		reader.observeSpawn(pool, "game_object");
		reader.observationsComplete();
		assertEquals(1, reader.read().get("recognizedFeatureCount").getAsInt());
		reader.observeDespawn(pool);
		assertEquals(0, reader.read().get("recognizedFeatureCount").getAsInt());
	}

	@Test
	public void boundsIndividualFeaturesWhileRetainingCompleteCounts()
	{
		int poolId = PohIcons.POOLS.getIds()[0];
		Tile[][][] tiles = new Tile[1][129][1];
		for (int index = 0; index < 129; index++)
		{
			GameObject pool = object(GameObject.class, poolId, new WorldPoint(1880 + index, 7050, 0));
			tiles[0][index][0] = tile(pool, null);
		}
		JsonObject poh = new PohSnapshotReader(client(new WorldPoint(1880, 7050, 0), scene(tiles))).read();
		assertEquals(129, poh.get("recognizedFeatureCount").getAsInt());
		assertEquals(129, poh.getAsJsonObject("featureCounts").get("pool").getAsInt());
		assertEquals(128, poh.getAsJsonArray("features").size());
		assertTrue(poh.get("truncated").getAsBoolean());
	}

	private static Client client(WorldPoint location, Scene scene)
	{
		return client(location, scene, 0);
	}

	private static Client client(WorldPoint location, Scene scene, int buildingMode)
	{
		return client(new WorldPoint[]{location}, scene, buildingMode);
	}

	private static Client client(WorldPoint[] location, Scene scene, int buildingMode)
	{
		Player player = (Player) Proxy.newProxyInstance(Player.class.getClassLoader(), new Class<?>[]{Player.class},
			(proxy, method, args) ->
			{
				if ("getWorldLocation".equals(method.getName()))
				{
					return location[0];
				}
				throw new AssertionError(method.getName());
			});
		return (Client) Proxy.newProxyInstance(Client.class.getClassLoader(), new Class<?>[]{Client.class},
			(proxy, method, args) ->
			{
				switch (method.getName())
				{
					case "getLocalPlayer": return player;
					case "isInInstancedRegion": return false;
					case "getTickCount": return 123;
					case "getVarbitValue": return buildingMode;
					case "getWidget": return null;
					case "getScene": return scene;
					case "getObjectDefinition": return definition((int) args[0]);
					default: throw new AssertionError(method.getName());
				}
			});
	}

	private static Scene scene(Tile[][][] tiles)
	{
		return (Scene) Proxy.newProxyInstance(Scene.class.getClassLoader(), new Class<?>[]{Scene.class},
			(proxy, method, args) ->
			{
				if ("getTiles".equals(method.getName()))
				{
					return tiles;
				}
				throw new AssertionError(method.getName());
			});
	}

	private static Tile tile(GameObject object, DecorativeObject decorative)
	{
		return (Tile) Proxy.newProxyInstance(Tile.class.getClassLoader(), new Class<?>[]{Tile.class},
			(proxy, method, args) ->
			{
				switch (method.getName())
				{
					case "getGameObjects": return new GameObject[]{object};
					case "getDecorativeObject": return decorative;
					default: throw new AssertionError(method.getName());
				}
			});
	}

	@SuppressWarnings("unchecked")
	private static <T extends TileObject> T object(Class<T> type, int id, WorldPoint location)
	{
		return (T) Proxy.newProxyInstance(type.getClassLoader(), new Class<?>[]{type},
			(proxy, method, args) ->
			{
				switch (method.getName())
				{
					case "getId": return id;
					case "getWorldLocation": return location;
					default: throw new AssertionError(method.getName());
				}
			});
	}

	private static ObjectComposition definition(int id)
	{
		return (ObjectComposition) Proxy.newProxyInstance(ObjectComposition.class.getClassLoader(),
			new Class<?>[]{ObjectComposition.class}, (proxy, method, args) ->
			{
				if ("getName".equals(method.getName()))
				{
					return "POH feature " + id;
				}
				throw new AssertionError(method.getName());
			});
	}
}
