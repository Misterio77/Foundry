package rs.m7.runelitemcp.protocol;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.io.InputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

public final class McpHttpServer implements AutoCloseable
{
	private static final int MAX_REQUEST_BYTES = 1024 * 1024;

	private final McpDispatcher dispatcher;
	private HttpServer server;
	private ExecutorService executor;

	public McpHttpServer(McpDispatcher dispatcher)
	{
		this.dispatcher = dispatcher;
	}

	public synchronized void start(int port) throws IOException
	{
		if (server != null)
		{
			throw new IllegalStateException("RuneLite MCP server is already running");
		}

		InetSocketAddress address = new InetSocketAddress(InetAddress.getByName("127.0.0.1"), port);
		HttpServer created = HttpServer.create(address, 32);
		ExecutorService workers = new ThreadPoolExecutor(
			2,
			4,
			30,
			TimeUnit.SECONDS,
			new ArrayBlockingQueue<>(32),
			new DaemonThreadFactory(),
			new ThreadPoolExecutor.AbortPolicy()
		);
		created.createContext("/mcp", this::handle);
		created.setExecutor(workers);
		server = created;
		executor = workers;
		try
		{
			created.start();
		}
		catch (RuntimeException ex)
		{
			close();
			throw ex;
		}
	}

	public synchronized int getPort()
	{
		if (server == null)
		{
			throw new IllegalStateException("RuneLite MCP server is not running");
		}
		return server.getAddress().getPort();
	}

	private void handle(HttpExchange exchange) throws IOException
	{
		try
		{
			if (!"POST".equals(exchange.getRequestMethod()))
			{
				exchange.getResponseHeaders().set("Allow", "POST");
				sendPlain(exchange, 405, "Method Not Allowed");
				return;
			}
			if (!isAllowedOrigin(exchange.getRequestHeaders().getFirst("Origin")))
			{
				sendPlain(exchange, 403, "Forbidden Origin");
				return;
			}

			String contentType = exchange.getRequestHeaders().getFirst("Content-Type");
			String mediaType = contentType == null ? "" : contentType.split(";", 2)[0].trim().toLowerCase(Locale.ROOT);
			if (!"application/json".equals(mediaType))
			{
				sendPlain(exchange, 415, "Content-Type must be application/json");
				return;
			}

			byte[] request = readBounded(exchange.getRequestBody());
			if (request == null)
			{
				sendPlain(exchange, 413, "Request body is too large");
				return;
			}

			DispatchResult result = dispatcher.dispatch(new String(request, StandardCharsets.UTF_8));
			if (result.getBody() == null)
			{
				exchange.sendResponseHeaders(result.getStatus(), -1);
				return;
			}

			byte[] response = result.getBody().getBytes(StandardCharsets.UTF_8);
			exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
			exchange.getResponseHeaders().set("Cache-Control", "no-store");
			exchange.sendResponseHeaders(result.getStatus(), response.length);
			exchange.getResponseBody().write(response);
		}
		finally
		{
			exchange.close();
		}
	}

	private static byte[] readBounded(InputStream input) throws IOException
	{
		byte[] value = input.readNBytes(MAX_REQUEST_BYTES + 1);
		return value.length > MAX_REQUEST_BYTES ? null : value;
	}

	private static boolean isAllowedOrigin(String origin)
	{
		if (origin == null)
		{
			return true;
		}
		try
		{
			URI uri = URI.create(origin);
			String host = uri.getHost();
			return ("http".equals(uri.getScheme()) || "https".equals(uri.getScheme()))
				&& ("127.0.0.1".equals(host) || "localhost".equalsIgnoreCase(host));
		}
		catch (IllegalArgumentException ex)
		{
			return false;
		}
	}

	private static void sendPlain(HttpExchange exchange, int status, String message) throws IOException
	{
		byte[] response = message.getBytes(StandardCharsets.UTF_8);
		exchange.getResponseHeaders().set("Content-Type", "text/plain; charset=utf-8");
		exchange.getResponseHeaders().set("Cache-Control", "no-store");
		exchange.sendResponseHeaders(status, response.length);
		exchange.getResponseBody().write(response);
	}

	@Override
	public synchronized void close()
	{
		if (server != null)
		{
			server.stop(0);
			server = null;
		}
		if (executor != null)
		{
			executor.shutdownNow();
			executor = null;
		}
	}

	private static final class DaemonThreadFactory implements ThreadFactory
	{
		private final AtomicInteger sequence = new AtomicInteger();

		@Override
		public Thread newThread(Runnable runnable)
		{
			Thread thread = new Thread(runnable, "runelite-mcp-http-" + sequence.incrementAndGet());
			thread.setDaemon(true);
			return thread;
		}
	}
}
