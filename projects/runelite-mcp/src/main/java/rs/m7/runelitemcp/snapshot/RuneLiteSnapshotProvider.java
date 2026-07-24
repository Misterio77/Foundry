package rs.m7.runelitemcp.snapshot;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicBoolean;
import javax.inject.Inject;
import net.runelite.api.Client;
import net.runelite.api.GameState;
import net.runelite.api.Player;
import net.runelite.api.Skill;
import net.runelite.api.coords.WorldPoint;
import net.runelite.client.callback.ClientThread;

public class RuneLiteSnapshotProvider implements SnapshotProvider
{
	private static final long SNAPSHOT_TIMEOUT_SECONDS = 2;

	private final Client client;
	private final ClientThread clientThread;

	@Inject
	public RuneLiteSnapshotProvider(Client client, ClientThread clientThread)
	{
		this.client = client;
		this.clientThread = clientThread;
	}

	@Override
	public JsonObject snapshot() throws Exception
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
				result.complete(readSnapshot());
			}
			catch (RuntimeException ex)
			{
				result.completeExceptionally(ex);
			}
		});

		try
		{
			return result.get(SNAPSHOT_TIMEOUT_SECONDS, TimeUnit.SECONDS);
		}
		catch (TimeoutException ex)
		{
			cancelled.set(true);
			throw new IllegalStateException("RuneLite did not produce a client snapshot in time");
		}
	}

	private JsonObject readSnapshot()
	{
		assert client.isClientThread();

		JsonObject snapshot = new JsonObject();
		GameState gameState = client.getGameState();
		snapshot.addProperty("gameState", gameState.name());
		snapshot.addProperty("world", client.getWorld());
		snapshot.addProperty("tickCount", client.getTickCount());

		Player player = client.getLocalPlayer();
		if (player != null)
		{
			JsonObject localPlayer = new JsonObject();
			localPlayer.addProperty("name", player.getName());
			localPlayer.addProperty("combatLevel", player.getCombatLevel());
			localPlayer.addProperty("animationId", player.getAnimation());

			WorldPoint location = player.getWorldLocation();
			JsonObject worldPoint = new JsonObject();
			worldPoint.addProperty("x", location.getX());
			worldPoint.addProperty("y", location.getY());
			worldPoint.addProperty("plane", location.getPlane());
			worldPoint.addProperty("regionId", location.getRegionID());
			localPlayer.add("worldPoint", worldPoint);
			snapshot.add("localPlayer", localPlayer);
		}

		JsonArray skills = new JsonArray();
		if (gameState == GameState.LOGGED_IN)
		{
			for (Skill skill : Skill.values())
			{
				JsonObject value = new JsonObject();
				value.addProperty("name", skill.getName());
				value.addProperty("realLevel", client.getRealSkillLevel(skill));
				value.addProperty("boostedLevel", client.getBoostedSkillLevel(skill));
				value.addProperty("experience", client.getSkillExperience(skill));
				skills.add(value);
			}
		}
		snapshot.add("skills", skills);
		return snapshot;
	}
}
