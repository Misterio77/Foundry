package rs.m7.runelitemcp;

import com.google.gson.Gson;
import com.google.inject.Provides;
import javax.inject.Inject;
import lombok.extern.slf4j.Slf4j;
import net.runelite.api.Client;
import net.runelite.api.GameState;
import net.runelite.api.MenuAction;
import net.runelite.api.events.DecorativeObjectDespawned;
import net.runelite.api.events.DecorativeObjectSpawned;
import net.runelite.api.events.GameObjectDespawned;
import net.runelite.api.events.GameObjectSpawned;
import net.runelite.api.events.GameStateChanged;
import net.runelite.api.events.GameTick;
import net.runelite.api.events.ItemContainerChanged;
import net.runelite.api.events.MenuOptionClicked;
import net.runelite.api.events.StatChanged;
import net.runelite.api.gameval.InterfaceID;
import net.runelite.api.gameval.ItemID;
import net.runelite.client.config.ConfigManager;
import net.runelite.client.eventbus.Subscribe;
import net.runelite.client.game.ItemManager;
import net.runelite.client.util.Text;
import net.runelite.client.plugins.Plugin;
import net.runelite.client.plugins.PluginDescriptor;
import rs.m7.runelitemcp.events.EventHistory;
import rs.m7.runelitemcp.events.RuneLiteEventCollector;
import rs.m7.runelitemcp.knowledge.OsrsWikiClient;
import rs.m7.runelitemcp.protocol.McpDispatcher;
import rs.m7.runelitemcp.protocol.McpHttpServer;
import rs.m7.runelitemcp.snapshot.AccountStateCache;
import rs.m7.runelitemcp.snapshot.RuneLiteSnapshotProvider;

@Slf4j
@SuppressWarnings("deprecation")
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

	@Inject
	private AccountStateCache accountStateCache;

	@Inject
	private Client client;

	@Inject
	private ItemManager itemManager;

	@Inject
	private OsrsWikiClient wiki;

	private EventHistory eventHistory;
	private McpHttpServer server;

	@Override
	protected void startUp() throws Exception
	{
		accountStateCache.clear();
		wiki.clear();
		eventHistory = new EventHistory();
		eventCollector.start(eventHistory);
		server = new McpHttpServer(new McpDispatcher(snapshots, eventHistory, wiki, gson));
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
		snapshots.clearPohAccount();
		accountStateCache.clear();
		wiki.clear();
		if (eventHistory != null)
		{
			eventHistory.close();
			eventHistory = null;
		}
	}

	@Subscribe
	public void onGameStateChanged(GameStateChanged event)
	{
		GameState state = event.getGameState();
		if (state == GameState.LOADING || state == GameState.LOGIN_SCREEN
			|| state == GameState.LOGIN_SCREEN_AUTHENTICATOR)
		{
			snapshots.changePohScene();
		}
		else if (state == GameState.LOGGED_IN)
		{
			snapshots.completePohObservations();
		}
		if (state == GameState.LOGIN_SCREEN || state == GameState.LOGIN_SCREEN_AUTHENTICATOR)
		{
			snapshots.clearPohAccount();
			accountStateCache.clear();
		}
		eventCollector.onGameStateChanged(event);
	}

	@Subscribe
	public void onGameObjectSpawned(GameObjectSpawned event)
	{
		snapshots.observePohObjectSpawn(event.getGameObject(), "game_object");
	}

	@Subscribe
	public void onGameObjectDespawned(GameObjectDespawned event)
	{
		snapshots.observePohObjectDespawn(event.getGameObject());
	}

	@Subscribe
	public void onDecorativeObjectSpawned(DecorativeObjectSpawned event)
	{
		snapshots.observePohObjectSpawn(event.getDecorativeObject(), "decorative_object");
	}

	@Subscribe
	public void onDecorativeObjectDespawned(DecorativeObjectDespawned event)
	{
		snapshots.observePohObjectDespawn(event.getDecorativeObject());
	}

	@Subscribe
	public void onMenuOptionClicked(MenuOptionClicked event)
	{
		String evidence = selfPohEntryEvidence(event.getMenuEntry().getParam1(),
			event.getMenuEntry().getOption(), event.getMenuEntry().getTarget(),
			event.getMenuEntry().getItemId(), event.getMenuEntry().getType());
		if (evidence != null)
		{
			snapshots.observeSelfPohEntryAction(evidence);
		}
	}

	static String selfPohEntryEvidence(int widgetId, String option, String target,
		int itemId, MenuAction action)
	{
		String cleanOption = clean(option);
		String cleanTarget = clean(target);
		if (widgetId == InterfaceID.MagicSpellbook.TELEPORT_TO_YOUR_HOUSE
			&& "cast".equals(cleanOption))
		{
			return "teleport_to_house_spell";
		}
		if (itemId == ItemID.POH_TABLET_TELEPORTTOHOUSE && action == MenuAction.ITEM_FIRST_OPTION)
		{
			return "house_teleport_tablet";
		}
		if ("home".equals(cleanOption) && "portal".equals(cleanTarget) && isObjectAction(action))
		{
			return "house_portal_home_option";
		}
		return null;
	}

	private static String clean(String value)
	{
		return value == null ? "" : Text.removeTags(value).trim().toLowerCase(java.util.Locale.ROOT);
	}

	private static boolean isObjectAction(MenuAction action)
	{
		return action == MenuAction.GAME_OBJECT_FIRST_OPTION
			|| action == MenuAction.GAME_OBJECT_SECOND_OPTION
			|| action == MenuAction.GAME_OBJECT_THIRD_OPTION
			|| action == MenuAction.GAME_OBJECT_FOURTH_OPTION
			|| action == MenuAction.GAME_OBJECT_FIFTH_OPTION;
	}

	@Subscribe
	public void onStatChanged(StatChanged event)
	{
		eventCollector.onStatChanged(event);
	}

	@Subscribe
	public void onItemContainerChanged(ItemContainerChanged event)
	{
		accountStateCache.observe(event.getContainerId(), event.getItemContainer(), client.getTickCount());
		eventCollector.onItemContainerChanged(event);
	}

	@Subscribe
	public void onGameTick(GameTick event)
	{
		if (client.getLocalPlayer() != null)
		{
			String playerName = client.getLocalPlayer().getName();
			accountStateCache.bindPlayer(playerName);
			snapshots.bindPohPlayer(playerName);
		}
		accountStateCache.enrichMetadata(client, itemManager, 8);
		eventCollector.onGameTick();
	}

	@Provides
	RuneLiteMcpConfig provideConfig(ConfigManager configManager)
	{
		return configManager.getConfig(RuneLiteMcpConfig.class);
	}
}
