package rs.m7.runelitemcp.events;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.EnumSet;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.junit.Test;
import rs.m7.runelitemcp.events.EventPayloads.GameStateChange;
import rs.m7.runelitemcp.events.EventPayloads.ItemChange;
import rs.m7.runelitemcp.events.EventPayloads.ItemValue;
import rs.m7.runelitemcp.events.EventPayloads.ContainerChange;
import rs.m7.runelitemcp.events.EventPayloads.Location;
import rs.m7.runelitemcp.events.EventPayloads.MovementChange;
import rs.m7.runelitemcp.events.EventPayloads.SkillChange;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

public class EventHistoryTest
{
	private static final EventMetadata ACTIVE = new EventMetadata("active", "LOGGED_IN", 100);

	@Test
	public void returnsLatestWindowAndBidirectionalPages()
	{
		EventHistory history = new EventHistory(8);
		for (int index = 0; index < 6; index++)
		{
			history.appendBatch(ACTIVE, Collections.singletonList(event(
				index % 2 == 0 ? EventType.SKILL_CHANGED : EventType.MOVEMENT_CHANGED, index + 1)));
		}

		EventPage latest = history.query(query(null, null, null, Collections.emptySet(), 2));
		assertSequences(latest, 5, 6);
		assertTrue(latest.hasOlder());
		assertFalse(latest.hasNewer());
		assertEquals(6, latest.getPollAfterSequence());

		EventPage older = history.query(query(history.getGeneration(), null, 5L,
			Collections.emptySet(), 2));
		assertSequences(older, 3, 4);
		assertTrue(older.hasOlder());
		assertTrue(older.hasNewer());

		EventPage newer = history.query(query(history.getGeneration(), 2L, null,
			EnumSet.of(EventType.SKILL_CHANGED), 2));
		assertSequences(newer, 3, 5);
		assertTrue(newer.hasOlder());
		assertFalse(newer.hasNewer());
	}

	@Test
	public void reportsOverwriteGapsAndRejectsStaleGenerations()
	{
		EventHistory history = new EventHistory(3);
		for (int index = 0; index < 5; index++)
		{
			history.appendBatch(ACTIVE, Collections.singletonList(event(EventType.SKILL_CHANGED, index + 1)));
		}
		String generation = history.getGeneration();
		EventPage gap = history.query(query(generation, 0L, null, Collections.emptySet(), 10));
		assertTrue(gap.hasGap());
		assertEquals(Long.valueOf(3), gap.getOldestSequence());
		assertSequences(gap, 3, 4, 5);
		EventPage backwardGap = history.query(query(generation, null, 2L,
			Collections.emptySet(), 10));
		assertTrue(backwardGap.hasGap());
		assertTrue(backwardGap.getEvents().isEmpty());
		assertTrue(backwardGap.hasNewer());
		EventPage filteredGap = history.query(query(generation, 0L, null,
			EnumSet.of(EventType.MOVEMENT_CHANGED), 10));
		assertTrue(filteredGap.hasGap());
		assertTrue(filteredGap.getEvents().isEmpty());
		assertFalse(filteredGap.hasNewer());

		history.resetAndAppend(new EventMetadata("logged_out", "LOGIN_SCREEN", 0),
			event(EventType.GAME_STATE_CHANGED, 0));
		assertNotEquals(generation, history.getGeneration());
		try
		{
			history.query(query(generation, 5L, null, Collections.emptySet(), 10));
			fail("stale generation should fail");
		}
		catch (IllegalArgumentException expected)
		{
			assertTrue(expected.getMessage().contains("generation changed"));
		}
	}

	@Test
	public void rollsGenerationOnlyAfterUsingMaximumSequence()
	{
		EventHistory history = new EventHistory(3, Long.MAX_VALUE);
		String generation = history.getGeneration();
		history.appendBatch(ACTIVE, Collections.singletonList(event(EventType.SKILL_CHANGED, 1)));
		EventPage maximum = history.query(query(null, null, null, Collections.emptySet(), 10));
		assertSequences(maximum, Long.MAX_VALUE);
		assertEquals(generation, history.getGeneration());

		history.appendBatch(ACTIVE, Collections.singletonList(event(EventType.SKILL_CHANGED, 2)));
		assertNotEquals(generation, history.getGeneration());
		assertSequences(history.query(query(null, null, null, Collections.emptySet(), 10)), 1);
	}

	@Test
	public void defensivelyCopiesPayloadsAndCountsRejectedRecords()
	{
		EventHistory history = new EventHistory();
		List<ItemChange> changes = new ArrayList<>();
		changes.add(new ItemChange(0, null, null, new ItemValue(995, "Coins", 10)));
		ContainerChange payload = new ContainerChange(changes, false, 28);
		changes.clear();
		List<ItemChange> oversizedChanges = new ArrayList<>();
		String longName = String.join("", Collections.nCopies(64, "x"));
		for (int slot = 0; slot < 28; slot++)
		{
			oversizedChanges.add(new ItemChange(slot, null,
				new ItemValue(1, longName, 1), new ItemValue(2, longName, 1)));
		}
		history.appendBatch(ACTIVE, Arrays.asList(
			new PendingEvent(EventType.INVENTORY_CHANGED, 1, payload),
			new PendingEvent(EventType.INVENTORY_CHANGED, 1,
				new ContainerChange(oversizedChanges, false, 28))
		));

		EventPage page = history.query(query(null, null, null, Collections.emptySet(), 10));
		assertEquals(1, page.getEvents().size());
		assertEquals(1, page.getDroppedEvents());
		assertEquals(1, page.getEvents().get(0).toJson().getAsJsonObject("data")
			.getAsJsonArray("changes").size());
	}

	@Test
	public void linearizesConcurrentAppendsAndQueries() throws Exception
	{
		EventHistory history = new EventHistory();
		ExecutorService executor = Executors.newFixedThreadPool(4);
		CountDownLatch start = new CountDownLatch(1);
		List<Future<?>> futures = new ArrayList<>();
		for (int worker = 0; worker < 3; worker++)
		{
			futures.add(executor.submit(() ->
			{
				start.await();
				for (int index = 1; index <= 100; index++)
				{
					history.appendBatch(ACTIVE,
						Collections.singletonList(event(EventType.SKILL_CHANGED, index)));
				}
				return null;
			}));
		}
		futures.add(executor.submit(() ->
		{
			start.await();
			for (int index = 0; index < 300; index++)
			{
				history.query(query(null, null, null, Collections.emptySet(), 10));
			}
			return null;
		}));
		start.countDown();
		for (Future<?> future : futures)
		{
			future.get(5, TimeUnit.SECONDS);
		}
		executor.shutdownNow();
		EventPage page = history.query(query(null, null, null, Collections.emptySet(), 100));
		assertEquals(Long.valueOf(300), page.getNewestSequence());
		assertEquals(100, page.getEvents().size());
	}

	@Test
	public void validatesCursorShape()
	{
		EventHistory history = new EventHistory();
		for (EventQuery invalid : Arrays.asList(
			query(null, 0L, null, Collections.emptySet(), 10),
			query(history.getGeneration(), null, null, Collections.emptySet(), 10)
		))
		{
			try
			{
				history.query(invalid);
				fail("invalid cursor should fail");
			}
			catch (IllegalArgumentException expected)
			{
				// expected
			}
		}
		for (Runnable invalid : Arrays.<Runnable>asList(
			() -> query(history.getGeneration(), 0L, 1L, Collections.emptySet(), 10),
			() -> query(null, null, null, Collections.emptySet(), 0)
		))
		{
			try
			{
				invalid.run();
				fail("invalid query constructor should fail");
			}
			catch (IllegalArgumentException expected)
			{
				// expected
			}
		}
	}

	private static PendingEvent event(EventType type, int tick)
	{
		switch (type)
		{
			case SKILL_CHANGED:
				return new PendingEvent(type, tick, new SkillChange("Agility", 1, 1, 0, tick, 1));
			case MOVEMENT_CHANGED:
				return new PendingEvent(type, tick, new MovementChange(
					new Location(tick, 0, 0, 0), new Location(tick + 1, 0, 0, 0), true, -1));
			case GAME_STATE_CHANGED:
				return new PendingEvent(type, tick, new GameStateChange("LOADING", "LOGGED_IN", "active"));
			default:
				throw new IllegalArgumentException("Unsupported test event " + type);
		}
	}

	private static EventQuery query(String generation, Long after, Long before,
		java.util.Set<EventType> types, int limit)
	{
		return new EventQuery(generation, after, before, types, limit);
	}

	private static void assertSequences(EventPage page, long... expected)
	{
		assertEquals(expected.length, page.getEvents().size());
		for (int index = 0; index < expected.length; index++)
		{
			assertEquals(expected[index], page.getEvents().get(index).getSequence());
		}
	}
}
