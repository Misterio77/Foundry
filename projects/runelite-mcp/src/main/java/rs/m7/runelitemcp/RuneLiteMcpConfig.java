package rs.m7.runelitemcp;

import net.runelite.client.config.Config;
import net.runelite.client.config.ConfigGroup;
import net.runelite.client.config.ConfigItem;
import net.runelite.client.config.Range;

@ConfigGroup("runeliteMcp")
public interface RuneLiteMcpConfig extends Config
{
	@Range(min = 1024, max = 65535)
	@ConfigItem(
		keyName = "port",
		name = "MCP port",
		description = "IPv4 loopback port for the local MCP endpoint. Restart the plugin after changing it.",
		warning = "Local applications connecting to this port can read the RuneLite information exposed by this plugin."
	)
	default int port()
	{
		return 18471;
	}

	@ConfigItem(
		keyName = "wikiAccess",
		name = "Enable OSRS Wiki access",
		description = "Allow explicit MCP Wiki search and page requests.",
		warning = "Outbound summary: enabling this sends MediaWiki read parameters plus your requested search query/limit or page title to oldschool.runescape.wiki. Requests never follow HTTP redirects and include no account or gameplay state."
	)
	default boolean wikiAccess()
	{
		return false;
	}
}
