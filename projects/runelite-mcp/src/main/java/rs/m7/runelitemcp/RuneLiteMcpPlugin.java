package rs.m7.runelitemcp;

import com.google.gson.Gson;
import com.google.inject.Provides;
import javax.inject.Inject;
import lombok.extern.slf4j.Slf4j;
import net.runelite.api.events.GameStateChanged;
import net.runelite.api.events.GameTick;
import net.runelite.api.events.ItemContainerChanged;
import net.runelite.api.events.StatChanged;
import net.runelite.client.config.ConfigManager;
import net.runelite.client.eventbus.Subscribe;
import net.runelite.client.plugins.Plugin;
import net.runelite.client.plugins.PluginDescriptor;
import rs.m7.runelitemcp.events.EventHistory;
import rs.m7.runelitemcp.events.RuneLiteEventCollector;
import rs.m7.runelitemcp.protocol.McpDispatcher;
import rs.m7.runelitemcp.protocol.McpHttpServer;
import rs.m7.runelitemcp.snapshot.RuneLiteSnapshotProvider;

@Slf4j
@PluginDescriptor(
	name = "RuneLite MCP",
	description = "Exposes live, informational RuneLite state to local MCP clients",
	tags = {"mcp", "ai", "api", "local", "information"}
)
public class RuneLiteMcpPlugin extends Plugin
{
	@Inject
	private RuneLiteMcpConfig config;

	@Inject
	private RuneLiteSnapshotProvider snapshots;

	@Inject
	private Gson gson;

	@Inject
	private RuneLiteEventCollector eventCollector;

	private EventHistory eventHistory;
	private McpHttpServer server;

	@Override
	protected void startUp() throws Exception
	{
		eventHistory = new EventHistory();
		eventCollector.start(eventHistory);
		server = new McpHttpServer(new McpDispatcher(snapshots, eventHistory, gson));
		try
		{
			server.start(config.port());
		}
		catch (Exception ex)
		{
			server.close();
			server = null;
			eventCollector.stop();
			eventHistory.close();
			eventHistory = null;
			throw ex;
		}
		log.info("RuneLite MCP listening at http://127.0.0.1:{}/mcp", server.getPort());
	}

	@Override
	protected void shutDown()
	{
		if (server != null)
		{
			server.close();
			server = null;
		}
		eventCollector.stop();
		if (eventHistory != null)
		{
			eventHistory.close();
			eventHistory = null;
		}
	}

	@Subscribe
	public void onGameStateChanged(GameStateChanged event)
	{
		eventCollector.onGameStateChanged(event);
	}

	@Subscribe
	public void onStatChanged(StatChanged event)
	{
		eventCollector.onStatChanged(event);
	}

	@Subscribe
	public void onItemContainerChanged(ItemContainerChanged event)
	{
		eventCollector.onItemContainerChanged(event);
	}

	@Subscribe
	public void onGameTick(GameTick event)
	{
		eventCollector.onGameTick();
	}

	@Provides
	RuneLiteMcpConfig provideConfig(ConfigManager configManager)
	{
		return configManager.getConfig(RuneLiteMcpConfig.class);
	}
}
