package rs.m7.runelitemcp.snapshot;

import com.google.gson.JsonArray;
import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicBoolean;
import javax.inject.Inject;
import net.runelite.api.Actor;
import net.runelite.api.Client;
import net.runelite.api.GameState;
import net.runelite.api.NPC;
import net.runelite.api.Player;
import net.runelite.api.Skill;
import net.runelite.api.VarPlayer;
import net.runelite.api.Varbits;
import net.runelite.api.coords.WorldPoint;
import net.runelite.client.callback.ClientThread;

@SuppressWarnings("deprecation")
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

	JsonObject readSnapshot()
	{
		assert client.isClientThread();

		GameState gameState = client.getGameState();
		Player player = gameState == GameState.LOGGED_IN ? client.getLocalPlayer() : null;
		String state = state(gameState, player != null);
		boolean active = "active".equals(state);

		JsonObject snapshot = new JsonObject();
		snapshot.addProperty("state", state);
		snapshot.add("sample", sample(gameState));
		snapshot.add("session", session(active));
		snapshot.add("player", active ? player(player) : JsonNull.INSTANCE);
		snapshot.add("skills", skills(active));
		return snapshot;
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
		vitals.addProperty("specialAttackPercent", client.getVarpValue(VarPlayer.SPECIAL_ATTACK_PERCENT) / 10.0);
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
			value.addProperty("realLevel", client.getRealSkillLevel(skill));
			value.addProperty("boostedLevel", client.getBoostedSkillLevel(skill));
			value.addProperty("experience", client.getSkillExperience(skill));
			skills.add(value);
		}
		return skills;
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
