package rs.m7.runelitemcp.events;

import java.util.Locale;

public enum EventType
{
	GAME_STATE_CHANGED,
	SKILL_CHANGED,
	INVENTORY_CHANGED,
	EQUIPMENT_CHANGED,
	MOVEMENT_CHANGED,
	INTERACTION_CHANGED;

	public String wireName()
	{
		return name().toLowerCase(Locale.ROOT);
	}

	public static EventType fromWireName(String name)
	{
		for (EventType value : values())
		{
			if (value.wireName().equals(name))
			{
				return value;
			}
		}
		throw new IllegalArgumentException("Unknown event type: " + name);
	}
}
