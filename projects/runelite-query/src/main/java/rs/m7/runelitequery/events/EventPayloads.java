package rs.m7.runelitequery.events;

import com.google.gson.JsonArray;
import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;

public final class EventPayloads
{
	private static final int MAX_NAME_CHARS = 64;

	private EventPayloads()
	{
	}

	public interface Payload
	{
		JsonObject toJson();

		int maximumEncodedBytes();
	}

	public static final class GameStateChange implements Payload
	{
		private final String previous;
		private final String current;
		private final String state;

		public GameStateChange(String previous, String current, String state)
		{
			this.previous = sanitize(previous);
			this.current = sanitize(current);
			this.state = sanitize(state);
		}

		@Override
		public JsonObject toJson()
		{
			JsonObject json = new JsonObject();
			json.addProperty("previous", previous);
			json.addProperty("current", current);
			json.addProperty("state", state);
			return json;
		}

		@Override
		public int maximumEncodedBytes()
		{
			return 128 + encoded(previous) + encoded(current) + encoded(state);
		}
	}

	public static final class SkillChange implements Payload
	{
		private final String skill;
		private final int baseLevel;
		private final int currentLevel;
		private final int levelDelta;
		private final int experience;
		private final int experienceDelta;

		public SkillChange(String skill, int baseLevel, int currentLevel, int levelDelta,
			int experience, int experienceDelta)
		{
			if (baseLevel < 0 || currentLevel < 0 || experience < 0)
			{
				throw new IllegalArgumentException("Skill levels and experience must be nonnegative");
			}
			this.skill = sanitize(skill);
			this.baseLevel = baseLevel;
			this.currentLevel = currentLevel;
			this.levelDelta = levelDelta;
			this.experience = experience;
			this.experienceDelta = experienceDelta;
		}

		@Override
		public JsonObject toJson()
		{
			JsonObject json = new JsonObject();
			json.addProperty("skill", skill);
			json.addProperty("baseLevel", baseLevel);
			json.addProperty("currentLevel", currentLevel);
			json.addProperty("levelDelta", levelDelta);
			json.addProperty("experience", experience);
			json.addProperty("experienceDelta", experienceDelta);
			return json;
		}

		@Override
		public int maximumEncodedBytes()
		{
			return 256 + encoded(skill);
		}
	}

	public static final class ItemValue
	{
		private final int id;
		private final String name;
		private final int quantity;

		public ItemValue(int id, String name, int quantity)
		{
			if (id <= 0 || quantity <= 0)
			{
				throw new IllegalArgumentException("Item IDs must be nonnegative and quantities positive");
			}
			this.id = id;
			this.name = sanitizeNullable(name);
			this.quantity = quantity;
		}

		JsonObject toJson()
		{
			JsonObject json = new JsonObject();
			json.addProperty("id", id);
			json.addProperty("name", name);
			json.addProperty("quantity", quantity);
			return json;
		}

		int maximumEncodedBytes()
		{
			return 128 + encoded(name);
		}
	}

	public static final class ItemChange
	{
		private final int slot;
		private final String slotName;
		private final ItemValue before;
		private final ItemValue after;

		public ItemChange(int slot, String slotName, ItemValue before, ItemValue after)
		{
			if (slot < 0 || slot >= 28 || before == null && after == null)
			{
				throw new IllegalArgumentException("Item changes require a slot and at least one value");
			}
			this.slot = slot;
			this.slotName = sanitizeNullable(slotName);
			this.before = before;
			this.after = after;
		}

		JsonObject toJson()
		{
			JsonObject json = new JsonObject();
			json.addProperty("slot", slot);
			if (slotName != null)
			{
				json.addProperty("slotName", slotName);
			}
			json.add("before", before == null ? JsonNull.INSTANCE : before.toJson());
			json.add("after", after == null ? JsonNull.INSTANCE : after.toJson());
			return json;
		}

		int maximumEncodedBytes()
		{
			return 192 + encoded(slotName)
				+ (before == null ? 4 : before.maximumEncodedBytes())
				+ (after == null ? 4 : after.maximumEncodedBytes());
		}
	}

	public static final class ContainerChange implements Payload
	{
		private final List<ItemChange> changes;
		private final boolean truncated;
		private final int capacity;

		public ContainerChange(List<ItemChange> changes, boolean truncated, int capacity)
		{
			if (capacity != 14 && capacity != 28)
			{
				throw new IllegalArgumentException("Container capacity must be 14 or 28");
			}
			if (changes == null || changes.size() > capacity || changes.contains(null))
			{
				throw new IllegalArgumentException("Container changes exceed their nonnull capacity");
			}
			for (ItemChange change : changes)
			{
				if (change.slot >= capacity || capacity == 14 && change.slotName == null
					|| capacity == 28 && change.slotName != null)
				{
					throw new IllegalArgumentException("Container change slot metadata does not match capacity");
				}
			}
			this.changes = Collections.unmodifiableList(new ArrayList<>(changes));
			this.truncated = truncated;
			this.capacity = capacity;
		}

		int getCapacity()
		{
			return capacity;
		}

		@Override
		public JsonObject toJson()
		{
			JsonArray values = new JsonArray();
			for (ItemChange change : changes)
			{
				values.add(change.toJson());
			}
			JsonObject json = new JsonObject();
			json.add("changes", values);
			json.addProperty("truncated", truncated);
			return json;
		}

		@Override
		public int maximumEncodedBytes()
		{
			int size = 128;
			for (ItemChange change : changes)
			{
				size += change.maximumEncodedBytes();
			}
			return size;
		}
	}

	public static final class Location
	{
		private final int x;
		private final int y;
		private final int plane;
		private final int regionId;

		public Location(int x, int y, int plane, int regionId)
		{
			this.x = x;
			this.y = y;
			this.plane = plane;
			this.regionId = regionId;
		}

		JsonObject toJson()
		{
			JsonObject json = new JsonObject();
			json.addProperty("x", x);
			json.addProperty("y", y);
			json.addProperty("plane", plane);
			json.addProperty("regionId", regionId);
			return json;
		}

		@Override
		public boolean equals(Object other)
		{
			if (!(other instanceof Location))
			{
				return false;
			}
			Location value = (Location) other;
			return x == value.x && y == value.y && plane == value.plane && regionId == value.regionId;
		}

		@Override
		public int hashCode()
		{
			return Objects.hash(x, y, plane, regionId);
		}
	}

	public static final class MovementChange implements Payload
	{
		private final Location from;
		private final Location to;
		private final boolean moving;
		private final int animationId;

		public MovementChange(Location from, Location to, boolean moving, int animationId)
		{
			this.from = from;
			this.to = Objects.requireNonNull(to);
			this.moving = moving;
			this.animationId = animationId;
		}

		@Override
		public JsonObject toJson()
		{
			JsonObject json = new JsonObject();
			json.add("from", from == null ? JsonNull.INSTANCE : from.toJson());
			json.add("to", to.toJson());
			json.addProperty("moving", moving);
			json.addProperty("animationId", animationId);
			return json;
		}

		@Override
		public int maximumEncodedBytes()
		{
			return 384;
		}
	}

	public static final class Target
	{
		private final String type;
		private final Integer id;
		private final String name;
		private final Integer combatLevel;

		public Target(String type, Integer id, String name, Integer combatLevel)
		{
			if (!"npc".equals(type) && !"player".equals(type) && !"actor".equals(type))
			{
				throw new IllegalArgumentException("Unknown interaction target type");
			}
			this.type = sanitize(type);
			this.id = id;
			this.name = sanitizeNullable(name);
			this.combatLevel = combatLevel;
		}

		JsonObject toJson()
		{
			JsonObject json = new JsonObject();
			json.addProperty("type", type);
			if (id != null)
			{
				json.addProperty("id", id);
			}
			if ("npc".equals(type))
			{
				json.addProperty("name", name);
			}
			if (combatLevel != null)
			{
				json.addProperty("combatLevel", combatLevel);
			}
			return json;
		}

		boolean sameIdentity(Target other)
		{
			if (other == null || !type.equals(other.type))
			{
				return false;
			}
			return !"npc".equals(type) || Objects.equals(id, other.id);
		}

		int maximumEncodedBytes()
		{
			return 192 + encoded(type) + encoded(name);
		}
	}

	public static final class InteractionChange implements Payload
	{
		private final Target before;
		private final Target after;

		public InteractionChange(Target before, Target after)
		{
			this.before = before;
			this.after = after;
		}

		@Override
		public JsonObject toJson()
		{
			JsonObject json = new JsonObject();
			json.add("before", before == null ? JsonNull.INSTANCE : before.toJson());
			json.add("after", after == null ? JsonNull.INSTANCE : after.toJson());
			return json;
		}

		@Override
		public int maximumEncodedBytes()
		{
			return 128 + (before == null ? 4 : before.maximumEncodedBytes())
				+ (after == null ? 4 : after.maximumEncodedBytes());
		}
	}

	private static String sanitize(String value)
	{
		return Objects.requireNonNull(sanitizeNullable(value));
	}

	private static String sanitizeNullable(String value)
	{
		if (value == null)
		{
			return null;
		}
		StringBuilder clean = new StringBuilder(Math.min(value.length(), MAX_NAME_CHARS));
		for (int i = 0; i < value.length() && clean.length() < MAX_NAME_CHARS; i++)
		{
			char character = value.charAt(i);
			clean.append(Character.isISOControl(character) ? '?' : character);
		}
		return clean.toString();
	}

	private static int encoded(String value)
	{
		return value == null ? 4 : value.length() * 6;
	}
}
