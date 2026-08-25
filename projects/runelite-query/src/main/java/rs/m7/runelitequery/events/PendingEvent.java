package rs.m7.runelitequery.events;

import java.util.Objects;
import rs.m7.runelitequery.events.EventPayloads.Payload;

public final class PendingEvent
{
	private final EventType type;
	private final int tick;
	private final Payload payload;

	public PendingEvent(EventType type, int tick, Payload payload)
	{
		if (tick < 0)
		{
			throw new IllegalArgumentException("Event tick must be nonnegative");
		}
		this.type = Objects.requireNonNull(type);
		this.tick = tick;
		this.payload = Objects.requireNonNull(payload);
		if (!matchesType(type, payload))
		{
			throw new IllegalArgumentException("Event payload does not match event type");
		}
	}

	EventType getType()
	{
		return type;
	}

	int getTick()
	{
		return tick;
	}

	Payload getPayload()
	{
		return payload;
	}

	boolean fitsBound()
	{
		return payload.maximumEncodedBytes() + 128 <= EventHistory.MAX_RECORD_BYTES;
	}

	private static boolean matchesType(EventType type, Payload payload)
	{
		switch (type)
		{
			case GAME_STATE_CHANGED:
				return payload instanceof EventPayloads.GameStateChange;
			case SKILL_CHANGED:
				return payload instanceof EventPayloads.SkillChange;
			case INVENTORY_CHANGED:
				return payload instanceof EventPayloads.ContainerChange
					&& ((EventPayloads.ContainerChange) payload).getCapacity() == 28;
			case EQUIPMENT_CHANGED:
				return payload instanceof EventPayloads.ContainerChange
					&& ((EventPayloads.ContainerChange) payload).getCapacity() == 14;
			case MOVEMENT_CHANGED:
				return payload instanceof EventPayloads.MovementChange;
			case INTERACTION_CHANGED:
				return payload instanceof EventPayloads.InteractionChange;
			default:
				return false;
		}
	}
}
