package rs.m7.runelitequery.protocol;

import com.google.gson.JsonArray;
import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import rs.m7.runelitequery.snapshot.SnapshotType;

final class FixtureSnapshots
{
	private FixtureSnapshots()
	{
	}

	static JsonObject active(SnapshotType type)
	{
		JsonObject snapshot = envelope("active", "LOGGED_IN");
		snapshot.addProperty("fixtureType", type.name().toLowerCase());
		switch (type)
		{
			case GAME_CONTEXT:
				JsonObject session = new JsonObject();
				session.addProperty("world", 301);
				session.addProperty("accountType", "NORMAL");
				snapshot.add("session", session);
				JsonObject player = new JsonObject();
				player.addProperty("name", "Fixture player");
				player.addProperty("combatLevel", 126);
				snapshot.add("player", player);
				break;
			case SKILLS:
				JsonArray skills = new JsonArray();
				skills.add(skill("Attack", 80));
				skills.add(skill("Agility", 72));
				snapshot.add("skills", skills);
				break;
			case STATUS_EFFECTS:
				JsonObject effects = new JsonObject();
				effects.addProperty("availability", "current");
				effects.add("boosts", new JsonArray());
				effects.add("activePrayers", new JsonArray());
				effects.add("poison", JsonNull.INSTANCE);
				effects.add("timers", new JsonArray());
				snapshot.add("effects", effects);
				break;
			case CARRIED_ITEMS:
				JsonObject containers = new JsonObject();
				containers.add("inventory", container(28));
				containers.add("equipment", container(14));
				snapshot.add("containers", containers);
				break;
			default:
				JsonObject data = new JsonObject();
				data.addProperty("availability", "current");
				snapshot.add("fixture", data);
				break;
		}
		return snapshot;
	}

	static JsonObject unavailableContext(String state, String gameState)
	{
		JsonObject snapshot = envelope(state, gameState);
		JsonObject session = new JsonObject();
		session.add("world", JsonNull.INSTANCE);
		session.add("accountType", JsonNull.INSTANCE);
		snapshot.add("session", session);
		snapshot.add("player", JsonNull.INSTANCE);
		return snapshot;
	}

	private static JsonObject envelope(String state, String gameState)
	{
		JsonObject snapshot = new JsonObject();
		snapshot.addProperty("state", state);
		JsonObject sample = new JsonObject();
		sample.addProperty("gameState", gameState);
		sample.addProperty("tick", 123);
		snapshot.add("sample", sample);
		return snapshot;
	}

	private static JsonObject skill(String name, int level)
	{
		JsonObject skill = new JsonObject();
		skill.addProperty("name", name);
		skill.addProperty("baseLevel", level);
		skill.addProperty("currentLevel", level);
		skill.addProperty("experience", 1_000_000);
		return skill;
	}

	private static JsonObject container(int capacity)
	{
		JsonObject container = new JsonObject();
		container.addProperty("availability", "current");
		container.addProperty("capacity", capacity);
		container.addProperty("occupiedSlots", 0);
		container.addProperty("totalQuantity", 0);
		container.addProperty("truncated", false);
		container.add("items", new JsonArray());
		return container;
	}
}
