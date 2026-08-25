package rs.m7.runelitequery;

import net.runelite.client.config.Config;
import net.runelite.client.config.ConfigGroup;
import net.runelite.client.config.ConfigItem;
import net.runelite.client.config.Range;

@ConfigGroup("runeliteQuery")
public interface RuneLiteQueryConfig extends Config
{
	@Range(min = 1024, max = 65535)
	@ConfigItem(
		keyName = "port",
		name = "HTTP port",
		description = "IPv4 loopback port for the local read-only API. Restart the plugin after changing it.",
		warning = "Local applications connecting to this port can read the RuneLite information exposed by this plugin."
	)
	default int port()
	{
		return 18471;
	}
}
