package rs.m7.runelitequery.snapshot;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.IdentityHashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import net.runelite.api.Client;
import net.runelite.api.DecorativeObject;
import net.runelite.api.GameObject;
import net.runelite.api.ObjectComposition;
import net.runelite.api.Player;
import net.runelite.api.Scene;
import net.runelite.api.Tile;
import net.runelite.api.TileObject;
import net.runelite.api.coords.WorldPoint;
import net.runelite.api.gameval.InterfaceID;
import net.runelite.api.gameval.VarbitID;
import net.runelite.api.widgets.Widget;
import net.runelite.client.plugins.poh.PohIcons;

/** Reads only the currently loaded house, using RuneLite's own POH icon catalogue. */
@SuppressWarnings("deprecation")
final class PohSnapshotReader
{
	private static final int MAX_FEATURES = 128;
	private final Client client;
	private final IdentityHashMap<TileObject, String> observedObjects = new IdentityHashMap<>();
	private boolean observationsComplete;
	private int cachedRegionId;
	private Player cachedPlayer;
	private Scene cachedScene;
	private JsonObject cachedSnapshot;
	private String currentOwnership = "unknown";
	private String currentOwnershipEvidence;
	private JsonObject lastSelfSnapshot;
	private String boundPlayer;
	private String pendingSelfEntryEvidence;
	private long pendingSelfEntryDeadlineNanos;
	private boolean pendingSelfEntrySawLoading;

	PohSnapshotReader(Client client)
	{
		this.client = client;
	}

	JsonObject read()
	{
		JsonObject result = new JsonObject();
		result.addProperty("scope", "currently_loaded_house");
		result.addProperty("ownership", "unknown");
		Player player = client.getLocalPlayer();
		int regionId = RuneLiteAreaResolver.semanticRegionId(client, player);
		if (!RuneLiteAreaResolver.isAvailable())
		{
			result.addProperty("availability", "unavailable");
			result.addProperty("recognizedFeatureCount", 0);
			result.add("featureCounts", new JsonObject());
			result.add("features", new JsonArray());
			result.addProperty("truncated", false);
			return result;
		}
		if (!RuneLiteAreaResolver.isPlayerOwnedHouse(regionId))
		{
			if (lastSelfSnapshot != null)
			{
				JsonObject observed = lastSelfSnapshot.deepCopy();
				observed.addProperty("availability", "observed");
				observed.addProperty("scope", "last_observed_self_house");
				observed.addProperty("ownership", "self");
				return observed;
			}
			result.addProperty("availability", "not_in_house");
			result.addProperty("recognizedFeatureCount", 0);
			result.add("featureCounts", new JsonObject());
			result.add("features", new JsonArray());
			result.addProperty("truncated", false);
			return result;
		}

		addOwnership(result);
		int tick = client.getTickCount();
		Scene scene = client.getScene();
		if (cachedSnapshot != null && cachedRegionId == regionId
			&& cachedPlayer == player && cachedScene == scene)
		{
			JsonObject cached = cachedSnapshot.deepCopy();
			cached.addProperty("ownership", "unknown");
			cached.remove("ownershipEvidence");
			addOwnership(cached);
			rememberSelf(cached);
			return cached;
		}

		Tile[][][] tiles = scene == null ? null : scene.getTiles();
		if (tiles == null)
		{
			result.addProperty("availability", "unavailable");
			result.addProperty("recognizedFeatureCount", 0);
			result.add("featureCounts", new JsonObject());
			result.add("features", new JsonArray());
			result.addProperty("truncated", false);
			return result;
		}

		IdentityHashMap<TileObject, Boolean> seen = new IdentityHashMap<>();
		Accumulator accumulator = new Accumulator();
		if (observationsComplete)
		{
			observedObjects.forEach((object, objectType) -> add(accumulator, seen, object, objectType));
		}
		else
		{
			observedObjects.clear();
			for (Tile[][] plane : tiles)
			{
				if (plane == null)
				{
					continue;
				}
				for (Tile[] column : plane)
				{
					if (column == null)
					{
						continue;
					}
					for (Tile tile : column)
					{
						if (tile == null)
						{
							continue;
						}
						DecorativeObject decorative = tile.getDecorativeObject();
						rememberAndAdd(accumulator, seen, decorative, "decorative_object");
						GameObject[] objects = tile.getGameObjects();
						if (objects != null)
						{
							for (GameObject object : objects)
							{
								rememberAndAdd(accumulator, seen, object, "game_object");
							}
						}
					}
				}
			}
			observationsComplete = true;
		}

		accumulator.features.sort(Comparator.comparing((Feature feature) -> feature.key)
			.thenComparingInt(feature -> feature.id)
			.thenComparingInt(feature -> feature.location.getPlane())
			.thenComparingInt(feature -> feature.location.getX())
			.thenComparingInt(feature -> feature.location.getY()));
		JsonObject countJson = new JsonObject();
		accumulator.counts.forEach(countJson::addProperty);
		JsonArray featureJson = new JsonArray();
		for (Feature feature : accumulator.features)
		{
			featureJson.add(feature.json());
		}
		result.addProperty("availability", "current");
		result.addProperty("observedTick", tick);
		result.addProperty("observedAt", System.currentTimeMillis());
		result.addProperty("recognizedFeatureCount", accumulator.total);
		result.add("featureCounts", countJson);
		result.add("features", featureJson);
		result.addProperty("truncated", accumulator.total > MAX_FEATURES);
		cachedRegionId = regionId;
		cachedPlayer = player;
		cachedScene = scene;
		cachedSnapshot = result.deepCopy();
		rememberSelf(result);
		return result;
	}

	private void rememberAndAdd(Accumulator accumulator, IdentityHashMap<TileObject, Boolean> seen,
		TileObject object, String objectType)
	{
		if (object != null && PohIcons.getIcon(object.getId()) != null)
		{
			observedObjects.put(object, objectType);
		}
		add(accumulator, seen, object, objectType);
	}

	private void addOwnership(JsonObject result)
	{
		if (client.getVarbitValue(VarbitID.POH_BUILDING_MODE) != 0)
		{
			setCurrentOwnership(result, "self", "building_mode");
			return;
		}

		Widget expelGuests = client.getWidget(InterfaceID.PohOptions.EXPEL_GUESTS);
		Widget leaveHouse = client.getWidget(InterfaceID.PohOptions.LEAVE_HOUSE);
		if (expelGuests != null && !expelGuests.isHidden())
		{
			setCurrentOwnership(result, "self", "expel_guests_control");
		}
		else if (leaveHouse != null && !leaveHouse.isHidden())
		{
			setCurrentOwnership(result, "other", "guest_house_options");
		}
		else if (!"unknown".equals(currentOwnership))
		{
			result.addProperty("ownership", currentOwnership);
			result.addProperty("ownershipEvidence", currentOwnershipEvidence);
		}
	}

	private void setCurrentOwnership(JsonObject result, String ownership, String evidence)
	{
		currentOwnership = ownership;
		currentOwnershipEvidence = evidence;
		result.addProperty("ownership", ownership);
		result.addProperty("ownershipEvidence", evidence);
	}

	private void rememberSelf(JsonObject result)
	{
		if ("self".equals(result.get("ownership").getAsString()))
		{
			lastSelfSnapshot = result.deepCopy();
		}
	}

	private void add(Accumulator accumulator, IdentityHashMap<TileObject, Boolean> seen,
		TileObject object, String objectType)
	{
		if (object == null)
		{
			return;
		}
		PohIcons icon = PohIcons.getIcon(object.getId());
		if (icon == null || seen.put(object, Boolean.TRUE) != null)
		{
			return;
		}
		String key = icon.getImageResource();
		accumulator.total++;
		accumulator.counts.merge(key, 1, Integer::sum);
		if (accumulator.features.size() >= MAX_FEATURES)
		{
			return;
		}
		ObjectComposition definition = client.getObjectDefinition(object.getId());
		String name = definition == null ? null : definition.getName();
		if ("null".equalsIgnoreCase(name))
		{
			name = null;
		}
		accumulator.features.add(new Feature(object.getId(), name, key, objectType,
			object.getWorldLocation()));
	}

	void observeSpawn(TileObject object, String objectType)
	{
		if (object != null && PohIcons.getIcon(object.getId()) != null)
		{
			observedObjects.put(object, objectType);
			cachedSnapshot = null;
		}
	}

	void observeDespawn(TileObject object)
	{
		if (object != null && observedObjects.remove(object) != null)
		{
			cachedSnapshot = null;
		}
	}

	void observeSelfEntryAction(String evidence)
	{
		pendingSelfEntryEvidence = evidence;
		pendingSelfEntryDeadlineNanos = System.nanoTime() + java.util.concurrent.TimeUnit.SECONDS.toNanos(20);
		pendingSelfEntrySawLoading = false;
	}

	void observationsComplete()
	{
		observationsComplete = true;
		if (pendingSelfEntryEvidence == null)
		{
			return;
		}
		if (pendingSelfEntrySawLoading && System.nanoTime() <= pendingSelfEntryDeadlineNanos
			&& client.getLocalPlayer() != null
			&& RuneLiteAreaResolver.isPlayerOwnedHouse(
				RuneLiteAreaResolver.semanticRegionId(client, client.getLocalPlayer())))
		{
			currentOwnership = "self";
			currentOwnershipEvidence = pendingSelfEntryEvidence;
		}
		clearPendingEntry();
	}

	void refreshConfirmedSelfObservation()
	{
		Player player = client.getLocalPlayer();
		if (!"self".equals(currentOwnership) || player == null || cachedSnapshot != null
			|| !RuneLiteAreaResolver.isPlayerOwnedHouse(RuneLiteAreaResolver.semanticRegionId(client, player)))
		{
			return;
		}
		read();
	}

	void bindPlayer(String playerName)
	{
		if (boundPlayer != null && !boundPlayer.equals(playerName))
		{
			clearAccount();
		}
		boundPlayer = playerName;
	}

	void sceneChanged()
	{
		observedObjects.clear();
		observationsComplete = false;
		cachedRegionId = 0;
		cachedPlayer = null;
		cachedScene = null;
		cachedSnapshot = null;
		currentOwnership = "unknown";
		currentOwnershipEvidence = null;
		if (pendingSelfEntryEvidence != null)
		{
			pendingSelfEntrySawLoading = true;
		}
	}

	void clearAccount()
	{
		sceneChanged();
		lastSelfSnapshot = null;
		boundPlayer = null;
		clearPendingEntry();
	}

	private void clearPendingEntry()
	{
		pendingSelfEntryEvidence = null;
		pendingSelfEntryDeadlineNanos = 0;
		pendingSelfEntrySawLoading = false;
	}

	private static final class Accumulator
	{
		private int total;
		private final Map<String, Integer> counts = new LinkedHashMap<>();
		private final List<Feature> features = new ArrayList<>();
	}

	private static final class Feature
	{
		private final int id;
		private final String name;
		private final String key;
		private final String objectType;
		private final WorldPoint location;

		private Feature(int id, String name, String key, String objectType, WorldPoint location)
		{
			this.id = id;
			this.name = name;
			this.key = key;
			this.objectType = objectType;
			this.location = location;
		}

		private JsonObject json()
		{
			JsonObject value = new JsonObject();
			value.addProperty("id", id);
			value.addProperty("name", name);
			value.addProperty("feature", key);
			value.addProperty("objectType", objectType);
			JsonObject point = new JsonObject();
			point.addProperty("x", location.getX());
			point.addProperty("y", location.getY());
			point.addProperty("plane", location.getPlane());
			value.add("location", point);
			return value;
		}
	}
}
