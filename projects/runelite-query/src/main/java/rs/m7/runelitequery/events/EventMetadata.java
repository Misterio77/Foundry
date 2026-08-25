package rs.m7.runelitequery.events;

import java.util.Objects;

public final class EventMetadata
{
	private final String state;
	private final String gameState;
	private final int tick;

	public EventMetadata(String state, String gameState, int tick)
	{
		if (tick < 0)
		{
			throw new IllegalArgumentException("Event metadata tick must be nonnegative");
		}
		this.state = Objects.requireNonNull(state);
		this.gameState = Objects.requireNonNull(gameState);
		this.tick = tick;
	}

	public String getState()
	{
		return state;
	}

	public String getGameState()
	{
		return gameState;
	}

	public int getTick()
	{
		return tick;
	}
}
