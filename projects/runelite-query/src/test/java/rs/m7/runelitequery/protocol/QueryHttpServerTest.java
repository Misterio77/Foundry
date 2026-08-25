package rs.m7.runelitequery.protocol;

import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.io.InputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.Arrays;
import java.util.List;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import rs.m7.runelitequery.events.EventHistory;
import rs.m7.runelitequery.events.EventMetadata;
import rs.m7.runelitequery.events.EventPayloads.GameStateChange;
import rs.m7.runelitequery.events.EventType;
import rs.m7.runelitequery.events.PendingEvent;
import rs.m7.runelitequery.snapshot.SnapshotProvider;
import rs.m7.runelitequery.snapshot.SnapshotType;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class QueryHttpServerTest
{
	private QueryHttpServer server;
	private HttpClient client;
	private URI base;
	private RecordingProvider snapshots;
	private EventHistory eventHistory;

	@Before
	public void start() throws Exception
	{
		snapshots = new RecordingProvider();
		eventHistory = new EventHistory();
		eventHistory.appendBatch(new EventMetadata("active", "LOGGED_IN", 123),
			java.util.Collections.singletonList(new PendingEvent(EventType.GAME_STATE_CHANGED, 123,
				new GameStateChange("LOADING", "LOGGED_IN", "active"))));
		Gson gson = new Gson();
		server = new QueryHttpServer(new QueryDispatcher(snapshots, eventHistory, gson), gson);
		server.start(0);
		client = HttpClient.newHttpClient();
		base = URI.create("http://127.0.0.1:" + server.getPort());
	}

	@After
	public void stop()
	{
		server.close();
	}

	@Test
	public void servesEveryReadOnlyEndpointWithRawMockedShapes() throws Exception
	{
		List<String> paths = Arrays.asList(
			"/v1/context",
			"/v1/skills?name=Agility",
			"/v1/status-effects",
			"/v1/carried-items?container=inventory",
			"/v1/events?limit=3",
			"/v1/quests?state=in_progress&query=fairy&offset=0&limit=3",
			"/v1/achievement-diaries?region=varrock",
			"/v1/combat-achievements?tier=hard&completed=false&limit=3",
			"/v1/slayer?section=task",
			"/v1/grand-exchange",
			"/v1/stored-items?container=bank&query=rune&limit=3",
			"/v1/account-wealth",
			"/v1/collection-log",
			"/v1/poh",
			"/v1/item-prices?id=995&id=4151"
		);
		for (String path : paths)
		{
			HttpResponse<String> response = get(path, null);
			assertEquals(path, 200, response.statusCode());
			JsonObject body = new JsonParser().parse(response.body()).getAsJsonObject();
			assertTrue(path, body.has("state"));
			assertFalse(path, body.has("jsonrpc"));
			assertEquals("no-store", response.headers().firstValue("Cache-Control").orElse(""));
		}
	}

	@Test
	public void translatesRepeatedAndTypedQueryParameters() throws Exception
	{
		assertEquals(200, get("/v1/quests?state=in_progress&state=finished&query=fairy&offset=2&limit=10", null).statusCode());
		assertEquals(SnapshotType.QUESTS, snapshots.lastType);
		JsonObject arguments = snapshots.lastArguments;
		assertEquals(2, arguments.getAsJsonArray("states").size());
		assertEquals("fairy", arguments.get("query").getAsString());
		assertEquals(2, arguments.get("offset").getAsInt());
		assertEquals(10, arguments.get("limit").getAsInt());
	}

	@Test
	public void servesHealthAndValidOpenApi() throws Exception
	{
		JsonObject health = json(get("/v1/health", null));
		assertEquals("ok", health.get("status").getAsString());
		assertEquals("runelite-query", health.get("service").getAsString());

		JsonObject openApi = json(get("/v1/openapi.json", null));
		assertEquals("3.1.0", openApi.get("openapi").getAsString());
		assertTrue(openApi.getAsJsonObject("paths").has("/v1/context"));
		assertTrue(openApi.getAsJsonObject("paths").has("/v1/item-prices"));
		assertFalse(openApi.toString().toLowerCase().contains("mcp"));
		assertFalse(openApi.has("servers"));

		try (InputStream descriptor = QueryHttpServerTest.class.getResourceAsStream("/runelite-plugin.properties"))
		{
			assertTrue("plugin descriptor must be packaged", descriptor != null);
		}
	}

	@Test
	public void servesGenerationAwareEventCursors() throws Exception
	{
		JsonObject initial = json(get("/v1/events", null));
		JsonObject history = initial.getAsJsonObject("history");
		assertEquals(1, history.getAsJsonArray("events").size());
		String generation = history.get("generation").getAsString();

		JsonObject polled = json(get("/v1/events?generation=" + generation + "&after-sequence=1", null));
		assertEquals(0, polled.getAsJsonObject("history").getAsJsonArray("events").size());
	}

	@Test
	public void returnsStructuredHttpErrors() throws Exception
	{
		assertError("/v1/context?unknown=true", 400, "invalid_request");
		assertError("/v1/events?limit=101", 400, "invalid_request");
		assertError("/v1/events?after-sequence=0", 400, "invalid_request");
		assertError("/v1/events?generation=stale&after-sequence=0", 400, "invalid_request");
		assertError("/v1/events?generation=stale&after-sequence=0&before-sequence=1", 400, "invalid_request");
		assertError("/v1/combat-achievements?completed=yes", 400, "invalid_request");
		assertError("/v1/item-prices", 400, "invalid_request");
		assertError("/v1/nope", 404, "not_found");
	}

	@Test
	public void rejectsNonLoopbackOriginsAndMutationMethods() throws Exception
	{
		assertError("/v1/context", 403, "forbidden_origin", "https://example.com");

		HttpRequest post = HttpRequest.newBuilder(base.resolve("/v1/context"))
			.POST(HttpRequest.BodyPublishers.ofString("{}"))
			.build();
		HttpResponse<String> response = client.send(post, HttpResponse.BodyHandlers.ofString());
		assertEquals(405, response.statusCode());
		assertEquals("GET", response.headers().firstValue("Allow").orElse(""));
	}

	@Test
	public void doesNotExposeTheRemovedMcpEndpoint() throws Exception
	{
		HttpRequest request = HttpRequest.newBuilder(base.resolve("/mcp")).GET().build();
		assertEquals(404, client.send(request, HttpResponse.BodyHandlers.ofString()).statusCode());
	}

	private void assertError(String path, int status, String code) throws Exception
	{
		assertError(path, status, code, null);
	}

	private void assertError(String path, int status, String code, String origin) throws Exception
	{
		HttpResponse<String> response = get(path, origin);
		assertEquals(status, response.statusCode());
		assertEquals(code, new JsonParser().parse(response.body()).getAsJsonObject()
			.getAsJsonObject("error").get("code").getAsString());
	}

	private JsonObject json(HttpResponse<String> response)
	{
		assertEquals(200, response.statusCode());
		assertTrue(response.headers().firstValue("Content-Type").orElse("").startsWith("application/json"));
		return new JsonParser().parse(response.body()).getAsJsonObject();
	}

	private HttpResponse<String> get(String path, String origin) throws Exception
	{
		HttpRequest.Builder request = HttpRequest.newBuilder(base.resolve(path)).GET();
		if (origin != null)
		{
			request.header("Origin", origin);
		}
		return client.send(request.build(), HttpResponse.BodyHandlers.ofString());
	}

	private static final class RecordingProvider implements SnapshotProvider
	{
		private SnapshotType lastType;
		private JsonObject lastArguments;

		@Override
		public JsonObject snapshot(SnapshotType type)
		{
			lastType = type;
			lastArguments = new JsonObject();
			return FixtureSnapshots.active(type);
		}

		@Override
		public JsonObject snapshot(SnapshotType type, JsonObject arguments)
		{
			lastType = type;
			lastArguments = arguments.deepCopy();
			return FixtureSnapshots.active(type);
		}
	}
}
