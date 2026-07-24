package rs.m7.runelitemcp.knowledge;

import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.sun.net.httpserver.HttpServer;
import java.lang.reflect.Proxy;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.After;
import org.junit.Test;
import rs.m7.runelitemcp.RuneLiteMcpConfig;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

public class OsrsWikiClientTest
{
	private HttpServer server;

	@After
	public void stop()
	{
		if (server != null)
		{
			server.stop(0);
		}
	}

	@Test
	public void searchesCachesAndIdentifiesRequests() throws Exception
	{
		AtomicInteger requests = new AtomicInteger();
		server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
		server.createContext("/api.php", exchange ->
		{
			requests.incrementAndGet();
			assertEquals("GET", exchange.getRequestMethod());
			assertEquals("application/json", exchange.getRequestHeaders().getFirst("Accept"));
			assertTrue(exchange.getRequestHeaders().getFirst("User-Agent").startsWith("RuneLite-MCP/"));
			assertTrue(exchange.getRequestURI().getRawQuery().contains("srsearch=barrows%2B%2526%2B%25CE%25B2")
				|| exchange.getRequestURI().getRawQuery().contains("srsearch=barrows+%26+%CE%B2"));
			String body = "{\"query\":{\"search\":[{\"pageid\":1,\"title\":\"Barrows\",\"wordcount\":42,\"timestamp\":\"2026-01-01T00:00:00Z\"}]}}";
			exchange.getResponseHeaders().set("Content-Type", "application/json");
			exchange.sendResponseHeaders(200, body.getBytes(StandardCharsets.UTF_8).length);
			exchange.getResponseBody().write(body.getBytes(StandardCharsets.UTF_8));
			exchange.close();
		});
		server.start();
		OsrsWikiClient client = client(true);

		JsonObject first = client.search("barrows & β", 5);
		JsonObject second = client.search("barrows & β", 5);
		assertEquals("Barrows", first.getAsJsonArray("results").get(0).getAsJsonObject().get("title").getAsString());
		assertTrue(second.get("cached").getAsBoolean());
		assertEquals(1, requests.get());
	}

	@Test
	public void truncatesPlainTextPages() throws Exception
	{
		server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
		server.createContext("/api.php", exchange ->
		{
			String body = "{\"query\":{\"pages\":[{\"pageid\":2,\"title\":\"Abyssal whip\",\"extract\":\"abcdefghijklmnop\"}]}}";
			exchange.getResponseHeaders().set("Content-Type", "application/json");
			exchange.sendResponseHeaders(200, body.length());
			exchange.getResponseBody().write(body.getBytes(StandardCharsets.UTF_8));
			exchange.close();
		});
		server.start();
		JsonObject page = client(true).page("Abyssal whip", 10);
		assertEquals("abcdefghij", page.get("text").getAsString());
		assertTrue(page.get("truncated").getAsBoolean());
	}

	@Test
	public void neverFollowsRedirects() throws Exception
	{
		server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
		server.createContext("/api.php", exchange ->
		{
			exchange.getResponseHeaders().set("Location", "http://127.0.0.1:" + server.getAddress().getPort() + "/leak");
			exchange.sendResponseHeaders(302, -1);
			exchange.close();
		});
		server.createContext("/leak", exchange ->
		{
			throw new AssertionError("redirect target must not be reached");
		});
		server.start();
		try
		{
			client(true).search("private query", 1);
			fail("redirect should fail closed");
		}
		catch (IllegalStateException expected)
		{
			assertTrue(expected.getMessage().contains("HTTP 302"));
		}
	}

	@Test
	public void cancelsInFlightRequestsWhenCleared() throws Exception
	{
		CountDownLatch started = new CountDownLatch(1);
		CountDownLatch release = new CountDownLatch(1);
		server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
		server.createContext("/api.php", exchange ->
		{
			started.countDown();
			try
			{
				release.await(5, TimeUnit.SECONDS);
			}
			catch (InterruptedException ignored)
			{
				Thread.currentThread().interrupt();
			}
			exchange.close();
		});
		server.start();
		OsrsWikiClient client = client(true);
		ExecutorService executor = Executors.newSingleThreadExecutor();
		Future<?> request = executor.submit(() ->
		{
			try
			{
				client.search("slow", 1);
				fail("cleared request should not publish");
			}
			catch (Exception expected)
			{
				// expected
			}
		});
		assertTrue(started.await(1, TimeUnit.SECONDS));
		client.clear();
		release.countDown();
		request.get(1, TimeUnit.SECONDS);
		executor.shutdownNow();
	}

	@Test
	public void readsConfigurationDynamically()
	{
		boolean[] enabled = {false};
		RuneLiteMcpConfig config = (RuneLiteMcpConfig) Proxy.newProxyInstance(
			RuneLiteMcpConfig.class.getClassLoader(), new Class<?>[]{RuneLiteMcpConfig.class},
			(proxy, method, args) -> "wikiAccess".equals(method.getName()) && enabled[0]);
		OsrsWikiClient client = new OsrsWikiClient(config, new Gson());
		assertFalse(client.isEnabled());
		enabled[0] = true;
		assertTrue(client.isEnabled());
	}

	@Test
	public void failsClosedWhenOutboundAccessIsDisabled() throws Exception
	{
		server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
		server.start();
		try
		{
			client(false).search("anything", 1);
			fail("disabled Wiki access should fail");
		}
		catch (IllegalStateException expected)
		{
			assertTrue(expected.getMessage().contains("disabled"));
		}
	}

	private OsrsWikiClient client(boolean enabled)
	{
		return new OsrsWikiClient(enabled, new Gson(),
			java.net.URI.create("http://127.0.0.1:" + server.getAddress().getPort() + "/api.php"));
	}
}
