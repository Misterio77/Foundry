package rs.m7.runelitemcp.events;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Deque;
import java.util.List;
import java.util.Set;
import java.util.UUID;

public final class EventHistory implements AutoCloseable
{
	public static final int DEFAULT_CAPACITY = 512;
	public static final int MAX_RECORD_BYTES = 16 * 1024;

	private final int capacity;
	private final Deque<EventRecord> records = new ArrayDeque<>();
	private String generation = UUID.randomUUID().toString();
	private long nextSequence = 1;
	private boolean rolloverPending;
	private long droppedEvents;
	private EventMetadata metadata = new EventMetadata("loading", "UNKNOWN", 0);
	private boolean closed;

	public EventHistory()
	{
		this(DEFAULT_CAPACITY);
	}

	EventHistory(int capacity)
	{
		this(capacity, 1);
	}

	EventHistory(int capacity, long nextSequence)
	{
		if (capacity <= 0 || nextSequence <= 0)
		{
			throw new IllegalArgumentException("capacity and next sequence must be positive");
		}
		this.capacity = capacity;
		this.nextSequence = nextSequence;
	}

	public synchronized void updateState(EventMetadata metadata)
	{
		ensureOpen();
		this.metadata = metadata;
	}

	public synchronized void appendBatch(EventMetadata metadata, List<PendingEvent> pending)
	{
		ensureOpen();
		this.metadata = metadata;
		for (PendingEvent event : pending)
		{
			append(event);
		}
	}

	public synchronized void resetAndAppend(EventMetadata metadata, PendingEvent transition)
	{
		ensureOpen();
		reset(metadata);
		if (transition != null)
		{
			append(transition);
		}
	}

	public synchronized EventPage query(EventQuery query)
	{
		ensureOpen();
		validateCursor(query);

		List<EventRecord> retained = new ArrayList<>(records);
		Long oldest = retained.isEmpty() ? null : retained.get(0).getSequence();
		Long newest = retained.isEmpty() ? null : retained.get(retained.size() - 1).getSequence();
		boolean gap = false;
		Long lowerExclusive = query.getAfterSequence();

		if (oldest != null && query.getAfterSequence() != null && query.getAfterSequence() < oldest - 1)
		{
			gap = true;
			lowerExclusive = oldest - 1;
		}
		if (oldest != null && query.getBeforeSequence() != null && query.getBeforeSequence() < oldest)
		{
			gap = true;
			return new EventPage(metadata, generation, oldest, newest, false, hasMatching(retained, query.getTypes()),
				true, droppedEvents, query.getDirection(), Collections.emptyList());
		}

		List<EventRecord> matching = new ArrayList<>();
		for (EventRecord record : retained)
		{
			if ((lowerExclusive == null || record.getSequence() > lowerExclusive)
				&& (query.getBeforeSequence() == null || record.getSequence() < query.getBeforeSequence())
				&& matches(record, query.getTypes()))
			{
				matching.add(record);
			}
		}

		List<EventRecord> selected;
		if (query.getDirection() == EventQuery.Direction.FORWARD)
		{
			selected = matching.subList(0, Math.min(query.getLimit(), matching.size()));
		}
		else
		{
			int from = Math.max(0, matching.size() - query.getLimit());
			selected = matching.subList(from, matching.size());
		}
		selected = new ArrayList<>(selected);

		Long first = selected.isEmpty() ? null : selected.get(0).getSequence();
		Long last = selected.isEmpty() ? null : selected.get(selected.size() - 1).getSequence();
		boolean hasOlder = first != null && hasMatchingBefore(retained, query.getTypes(), first);
		boolean hasNewer = last != null && hasMatchingAfter(retained, query.getTypes(), last);
		return new EventPage(metadata, generation, oldest, newest, hasOlder, hasNewer, gap,
			droppedEvents, query.getDirection(), selected);
	}

	public synchronized String getGeneration()
	{
		return generation;
	}

	@Override
	public synchronized void close()
	{
		closed = true;
		records.clear();
		generation = UUID.randomUUID().toString();
		nextSequence = 1;
		rolloverPending = false;
		droppedEvents = 0;
		metadata = new EventMetadata("loading", "UNKNOWN", 0);
	}

	private void append(PendingEvent pending)
	{
		if (!pending.fitsBound())
		{
			droppedEvents++;
			return;
		}
		if (rolloverPending)
		{
			reset(metadata);
		}
		EventRecord record = new EventRecord(nextSequence, pending);
		if (nextSequence == Long.MAX_VALUE)
		{
			rolloverPending = true;
		}
		else
		{
			nextSequence++;
		}
		if (records.size() == capacity)
		{
			records.removeFirst();
		}
		records.addLast(record);
	}

	private void reset(EventMetadata metadata)
	{
		records.clear();
		generation = UUID.randomUUID().toString();
		nextSequence = 1;
		rolloverPending = false;
		droppedEvents = 0;
		this.metadata = metadata;
	}

	private void validateCursor(EventQuery query)
	{
		boolean hasCursor = query.getAfterSequence() != null || query.getBeforeSequence() != null;
		if (hasCursor != (query.getGeneration() != null))
		{
			throw new IllegalArgumentException("generation is required with a cursor and forbidden without one");
		}
		if (query.getGeneration() != null && !generation.equals(query.getGeneration()))
		{
			throw new IllegalArgumentException("Event history generation changed; query again without a cursor");
		}
		if (query.getAfterSequence() != null && query.getBeforeSequence() != null)
		{
			throw new IllegalArgumentException("afterSequence and beforeSequence are mutually exclusive");
		}
		if (query.getAfterSequence() != null && query.getAfterSequence() < 0)
		{
			throw new IllegalArgumentException("afterSequence must be nonnegative");
		}
		if (query.getBeforeSequence() != null && query.getBeforeSequence() <= 0)
		{
			throw new IllegalArgumentException("beforeSequence must be positive");
		}
		long newest = records.isEmpty() ? 0 : records.getLast().getSequence();
		Long cursor = query.getAfterSequence() != null ? query.getAfterSequence() : query.getBeforeSequence();
		if (cursor != null && cursor > newest)
		{
			throw new IllegalArgumentException("Event cursor is beyond the current history");
		}
	}

	private static boolean matches(EventRecord record, Set<EventType> types)
	{
		return types.isEmpty() || types.contains(record.getType());
	}

	private static boolean hasMatching(List<EventRecord> records, Set<EventType> types)
	{
		for (EventRecord record : records)
		{
			if (matches(record, types))
			{
				return true;
			}
		}
		return false;
	}

	private static boolean hasMatchingBefore(List<EventRecord> records, Set<EventType> types, long sequence)
	{
		for (EventRecord record : records)
		{
			if (record.getSequence() >= sequence)
			{
				return false;
			}
			if (matches(record, types))
			{
				return true;
			}
		}
		return false;
	}

	private static boolean hasMatchingAfter(List<EventRecord> records, Set<EventType> types, long sequence)
	{
		for (int index = records.size() - 1; index >= 0; index--)
		{
			EventRecord record = records.get(index);
			if (record.getSequence() <= sequence)
			{
				return false;
			}
			if (matches(record, types))
			{
				return true;
			}
		}
		return false;
	}

	private void ensureOpen()
	{
		if (closed)
		{
			throw new IllegalStateException("Event history is closed");
		}
	}
}
