package rs.m7.runelitemcp;

import com.google.gson.Gson;
import com.google.inject.Provides;
import javax.inject.Inject;
import lombok.extern.slf4j.Slf4j;
import net.runelite.client.config.ConfigManager;
import net.runelite.client.plugins.Plugin;
import net.runelite.client.plugins.PluginDescriptor;
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

	private McpHttpServer server;

	@Override
	protected void startUp() throws Exception
	{
		server = new McpHttpServer(new McpDispatcher(snapshots, gson));
		try
		{
			server.start(config.port());
		}
		catch (Exception ex)
		{
			server.close();
			server = null;
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
	}

	@Provides
	RuneLiteMcpConfig provideConfig(ConfigManager configManager)
	{
		return configManager.getConfig(RuneLiteMcpConfig.class);
	}
}
