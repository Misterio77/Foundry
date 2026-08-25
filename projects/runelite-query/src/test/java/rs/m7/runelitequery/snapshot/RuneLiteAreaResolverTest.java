package rs.m7.runelitequery.snapshot;

import com.google.gson.JsonObject;
import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

public class RuneLiteAreaResolverTest
{
	@Test
	public void reusesRuneLiteDiscordRegionCatalogue()
	{
		JsonObject area = RuneLiteAreaResolver.resolve(12598);
		assertEquals("Grand Exchange", area.get("name").getAsString());
		assertEquals("regions", area.get("category").getAsString());
		assertEquals("runelite_discord_regions", area.get("source").getAsString());
	}

	@Test
	public void returnsNullOutsideRuneLiteCatalogue()
	{
		assertNull(RuneLiteAreaResolver.resolve(0));
	}
}
