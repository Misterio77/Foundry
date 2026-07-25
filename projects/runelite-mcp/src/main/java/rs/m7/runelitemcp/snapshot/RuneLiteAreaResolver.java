package rs.m7.runelitemcp.snapshot;

import com.google.gson.JsonObject;
import java.lang.reflect.Method;
import java.util.Locale;
import javax.annotation.Nullable;

/**
 * Narrow adapter over RuneLite's built-in Discord region catalogue. RuneLite
 * keeps the catalogue package-private, so reflection is required to reuse it
 * without maintaining a divergent copy.
 */
final class RuneLiteAreaResolver
{
	private static final String EVENT_TYPE = "net.runelite.client.plugins.discord.DiscordGameEventType";
	private static final Resolver RESOLVER = load();

	private RuneLiteAreaResolver()
	{
	}

	@Nullable
	static JsonObject resolve(int regionId)
	{
		return RESOLVER.resolve(regionId);
	}

	private static Resolver load()
	{
		try
		{
			Class<?> eventType = Class.forName(EVENT_TYPE);
			Method fromRegion = eventType.getDeclaredMethod("fromRegion", int.class);
			Method getState = eventType.getDeclaredMethod("getState");
			Method getAreaType = eventType.getDeclaredMethod("getDiscordAreaType");
			fromRegion.setAccessible(true);
			getState.setAccessible(true);
			getAreaType.setAccessible(true);
			return regionId -> invoke(fromRegion, getState, getAreaType, regionId);
		}
		catch (ReflectiveOperationException | RuntimeException | LinkageError ex)
		{
			return regionId -> null;
		}
	}

	@Nullable
	private static JsonObject invoke(Method fromRegion, Method getState, Method getAreaType, int regionId)
	{
		try
		{
			Object event = fromRegion.invoke(null, regionId);
			if (event == null)
			{
				return null;
			}

			Object name = getState.invoke(event);
			Object category = getAreaType.invoke(event);
			if (!(name instanceof String) || category == null)
			{
				return null;
			}

			JsonObject area = new JsonObject();
			area.addProperty("name", (String) name);
			area.addProperty("category", category.toString().toLowerCase(Locale.ROOT));
			area.addProperty("source", "runelite_discord_regions");
			return area;
		}
		catch (ReflectiveOperationException | RuntimeException ex)
		{
			return null;
		}
	}

	private interface Resolver
	{
		@Nullable
		JsonObject resolve(int regionId);
	}
}
