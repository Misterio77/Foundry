package rs.m7.runelitequery.events;

import com.google.gson.JsonObject;
import rs.m7.runelitequery.events.EventPayloads.Payload;

public final class EventRecord
{
	private final long sequence;
	private final EventType type;
	private final int tick;
	private final Payload payload;

	EventRecord(long sequence, PendingEvent pending)
	{
		this.sequence = sequence;
		this.type = pending.getType();
		this.tick = pending.getTick();
		this.payload = pending.getPayload();
	}

	public long getSequence()
	{
		return sequence;
	}

	public EventType getType()
	{
		return type;
	}

	public JsonObject toJson()
	{
		JsonObject json = new JsonObject();
		json.addProperty("sequence", sequence);
		json.addProperty("tick", tick);
		json.addProperty("type", type.wireName());
		json.add("data", payload.toJson());
		return json;
	}

	boolean fitsBound()
	{
		return payload.maximumEncodedBytes() + 128 <= EventHistory.MAX_RECORD_BYTES;
	}
}
