package rs.m7.runelitequery.events;

import java.util.Collections;
import java.util.EnumSet;
import java.util.Set;

public final class EventQuery
{
	public enum Direction
	{
		LATEST,
		FORWARD,
		BACKWARD
	}

	private final String generation;
	private final Long afterSequence;
	private final Long beforeSequence;
	private final Set<EventType> types;
	private final int limit;

	public EventQuery(String generation, Long afterSequence, Long beforeSequence,
		Set<EventType> types, int limit)
	{
		if (types == null || limit < 1 || limit > 100)
		{
			throw new IllegalArgumentException("Event query types and limit are invalid");
		}
		if (afterSequence != null && beforeSequence != null
			|| afterSequence != null && afterSequence < 0
			|| beforeSequence != null && beforeSequence <= 0)
		{
			throw new IllegalArgumentException("Event query cursor is invalid");
		}
		this.generation = generation;
		this.afterSequence = afterSequence;
		this.beforeSequence = beforeSequence;
		this.types = types.isEmpty()
			? Collections.emptySet()
			: Collections.unmodifiableSet(EnumSet.copyOf(types));
		this.limit = limit;
	}

	String getGeneration()
	{
		return generation;
	}

	Long getAfterSequence()
	{
		return afterSequence;
	}

	Long getBeforeSequence()
	{
		return beforeSequence;
	}

	Set<EventType> getTypes()
	{
		return types;
	}

	int getLimit()
	{
		return limit;
	}

	Direction getDirection()
	{
		return afterSequence != null ? Direction.FORWARD
			: beforeSequence != null ? Direction.BACKWARD : Direction.LATEST;
	}
}
