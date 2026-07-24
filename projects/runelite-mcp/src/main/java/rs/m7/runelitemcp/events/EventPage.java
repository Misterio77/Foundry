package rs.m7.runelitemcp.events;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public final class EventPage
{
	private final EventMetadata metadata;
	private final String generation;
	private final Long oldestSequence;
	private final Long newestSequence;
	private final long pollAfterSequence;
	private final boolean hasOlder;
	private final boolean hasNewer;
	private final boolean gap;
	private final long droppedEvents;
	private final EventQuery.Direction direction;
	private final List<EventRecord> events;

	EventPage(EventMetadata metadata, String generation, Long oldestSequence, Long newestSequence,
		boolean hasOlder, boolean hasNewer, boolean gap, long droppedEvents,
		EventQuery.Direction direction, List<EventRecord> events)
	{
		this.metadata = metadata;
		this.generation = generation;
		this.oldestSequence = oldestSequence;
		this.newestSequence = newestSequence;
		this.pollAfterSequence = newestSequence == null ? 0 : newestSequence;
		this.hasOlder = hasOlder;
		this.hasNewer = hasNewer;
		this.gap = gap;
		this.droppedEvents = droppedEvents;
		this.direction = direction;
		this.events = Collections.unmodifiableList(new ArrayList<>(events));
	}

	public EventMetadata getMetadata()
	{
		return metadata;
	}

	public String getGeneration()
	{
		return generation;
	}

	public Long getOldestSequence()
	{
		return oldestSequence;
	}

	public Long getNewestSequence()
	{
		return newestSequence;
	}

	public long getPollAfterSequence()
	{
		return pollAfterSequence;
	}

	public boolean hasOlder()
	{
		return hasOlder;
	}

	public boolean hasNewer()
	{
		return hasNewer;
	}

	public boolean hasGap()
	{
		return gap;
	}

	public long getDroppedEvents()
	{
		return droppedEvents;
	}

	public EventQuery.Direction getDirection()
	{
		return direction;
	}

	public List<EventRecord> getEvents()
	{
		return events;
	}
}
