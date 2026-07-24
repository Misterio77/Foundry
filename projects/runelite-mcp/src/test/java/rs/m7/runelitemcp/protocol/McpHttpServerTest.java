package rs.m7.runelitemcp.protocol;

import com.google.gson.Gson;
import com.google.gson.JsonObject;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

public class McpHttpServerTest
{
	private McpHttpServer server;
	private HttpClient client;
	private URI endpoint;

	@Before
	public void start() throws Exception
	{
		server = new McpHttpServer(new McpDispatcher(type -> new JsonObject(), new Gson()));
		server.start(0);
		client = HttpClient.newHttpClient();
		endpoint = URI.create("http://127.0.0.1:" + server.getPort() + "/mcp");
	}

	@After
	public void stop()
	{
		server.close();
	}

	@Test
	public void servesJsonRpcOnlyOnLoopbackEndpoint() throws Exception
	{
		HttpResponse<String> response = send("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}", null);
		assertEquals(200, response.statusCode());
		assertTrue(response.headers().firstValue("Content-Type").orElse("").startsWith("application/json"));
		assertTrue(response.body().contains("\"result\":{}"));
	}

	@Test
	public void requiresNegotiatedProtocolVersionAfterInitialization() throws Exception
	{
		HttpRequest missing = HttpRequest.newBuilder(endpoint)
			.header("Content-Type", "application/json")
			.POST(HttpRequest.BodyPublishers.ofString("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}"))
			.build();
		assertEquals(400, client.send(missing, HttpResponse.BodyHandlers.ofString()).statusCode());

		HttpRequest unsupported = HttpRequest.newBuilder(endpoint)
			.header("Content-Type", "application/json")
			.header("MCP-Protocol-Version", "2025-06-18")
			.POST(HttpRequest.BodyPublishers.ofString("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}"))
			.build();
		assertEquals(400, client.send(unsupported, HttpResponse.BodyHandlers.ofString()).statusCode());

		HttpRequest initialize = HttpRequest.newBuilder(endpoint)
			.header("Content-Type", "application/json")
			.POST(HttpRequest.BodyPublishers.ofString("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{},\"clientInfo\":{\"name\":\"test\",\"version\":\"1\"}}}"))
			.build();
		assertEquals(200, client.send(initialize, HttpResponse.BodyHandlers.ofString()).statusCode());
	}

	@Test
	public void rejectsNonLoopbackBrowserOrigins() throws Exception
	{
		HttpResponse<String> response = send("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}", "https://example.com");
		assertEquals(403, response.statusCode());
	}

	@Test
	public void acceptsNotificationsWithoutResponseBody() throws Exception
	{
		HttpResponse<String> response = send("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}", null);
		assertEquals(202, response.statusCode());
		assertEquals("", response.body());
	}

	@Test
	public void rejectsOtherMethodsAndContentTypes() throws Exception
	{
		HttpRequest get = HttpRequest.newBuilder(endpoint).GET().build();
		assertEquals(405, client.send(get, HttpResponse.BodyHandlers.ofString()).statusCode());

		HttpRequest text = HttpRequest.newBuilder(endpoint)
			.header("Content-Type", "text/plain")
			.POST(HttpRequest.BodyPublishers.ofString("{}"))
			.build();
		assertEquals(415, client.send(text, HttpResponse.BodyHandlers.ofString()).statusCode());
	}

	private HttpResponse<String> send(String body, String origin) throws Exception
	{
		HttpRequest.Builder request = HttpRequest.newBuilder(endpoint)
			.header("Content-Type", "application/json")
			.header("Accept", "application/json, text/event-stream")
			.header("MCP-Protocol-Version", "2025-11-25")
			.POST(HttpRequest.BodyPublishers.ofString(body));
		if (origin != null)
		{
			request.header("Origin", origin);
		}
		return client.send(request.build(), HttpResponse.BodyHandlers.ofString());
	}
}
