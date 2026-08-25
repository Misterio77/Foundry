package rs.m7.runelitequery.protocol;

import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonPrimitive;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.math.BigDecimal;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

public final class QueryHttpServer implements AutoCloseable
{
	private static final int MAX_QUERY_BYTES = 16 * 1024;
	private static final String API_PREFIX = "/v1";

	private final QueryDispatcher dispatcher;
	private final Gson gson;
	private final byte[] openApi;
	private HttpServer server;
	private ExecutorService executor;

	public QueryHttpServer(QueryDispatcher dispatcher, Gson gson)
	{
		this.dispatcher = dispatcher;
		this.gson = gson.newBuilder().serializeNulls().create();
		this.openApi = readOpenApi();
	}

	public synchronized void start(int port) throws IOException
	{
		if (server != null)
		{
			throw new IllegalStateException("RuneLite Query server is already running");
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
		created.createContext(API_PREFIX, this::handle);
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
			throw new IllegalStateException("RuneLite Query server is not running");
		}
		return server.getAddress().getPort();
	}

	private void handle(HttpExchange exchange) throws IOException
	{
		try
		{
			if (!"GET".equals(exchange.getRequestMethod()))
			{
				exchange.getResponseHeaders().set("Allow", "GET");
				sendError(exchange, 405, "method_not_allowed", "Only GET is supported");
				return;
			}
			if (!isAllowedOrigin(exchange.getRequestHeaders().getFirst("Origin")))
			{
				sendError(exchange, 403, "forbidden_origin", "Browser Origin must be loopback");
				return;
			}

			URI requestUri = exchange.getRequestURI();
			String rawQuery = requestUri.getRawQuery();
			if (rawQuery != null && rawQuery.getBytes(StandardCharsets.UTF_8).length > MAX_QUERY_BYTES)
			{
				sendError(exchange, 414, "query_too_long", "Query string is too long");
				return;
			}

			String path = requestUri.getPath();
			if ((API_PREFIX + "/health").equals(path))
			{
				requireNoParameters(rawQuery);
				JsonObject health = new JsonObject();
				health.addProperty("status", "ok");
				health.addProperty("service", "runelite-query");
				health.addProperty("version", "1");
				sendJson(exchange, 200, gson.toJson(health).getBytes(StandardCharsets.UTF_8));
				return;
			}
			if ((API_PREFIX + "/openapi.json").equals(path))
			{
				requireNoParameters(rawQuery);
				sendJson(exchange, 200, openApi);
				return;
			}

			Route route = route(path, parseQuery(rawQuery));
			if (route == null)
			{
				sendError(exchange, 404, "not_found", "Unknown endpoint");
				return;
			}
			JsonObject result = dispatcher.query(route.operation, route.arguments);
			sendJson(exchange, 200, gson.toJson(result).getBytes(StandardCharsets.UTF_8));
		}
		catch (IllegalArgumentException ex)
		{
			sendError(exchange, 400, "invalid_request", ex.getMessage());
		}
		catch (Exception ex)
		{
			sendError(exchange, 500, "query_failed", "RuneLite query failed");
		}
		finally
		{
			exchange.close();
		}
	}

	private static Route route(String path, Map<String, List<String>> parameters)
	{
		JsonObject arguments = new JsonObject();
		switch (path)
		{
			case API_PREFIX + "/context":
				requireAllowed(parameters);
				return new Route("context", arguments);
			case API_PREFIX + "/skills":
				requireAllowed(parameters, "name");
				addStrings(arguments, "names", parameters.get("name"));
				return new Route("skills", arguments);
			case API_PREFIX + "/status-effects":
				requireAllowed(parameters);
				return new Route("status-effects", arguments);
			case API_PREFIX + "/carried-items":
				requireAllowed(parameters, "container");
				addStrings(arguments, "containers", parameters.get("container"));
				return new Route("carried-items", arguments);
			case API_PREFIX + "/events":
				requireAllowed(parameters, "generation", "after-sequence", "before-sequence", "type", "limit");
				addString(arguments, "generation", parameters.get("generation"));
				addInteger(arguments, "afterSequence", parameters.get("after-sequence"));
				addInteger(arguments, "beforeSequence", parameters.get("before-sequence"));
				addStrings(arguments, "types", parameters.get("type"));
				addInteger(arguments, "limit", parameters.get("limit"));
				return new Route("events", arguments);
			case API_PREFIX + "/quests":
				requireAllowed(parameters, "state", "query", "offset", "limit");
				addStrings(arguments, "states", parameters.get("state"));
				addString(arguments, "query", parameters.get("query"));
				addInteger(arguments, "offset", parameters.get("offset"));
				addInteger(arguments, "limit", parameters.get("limit"));
				return new Route("quests", arguments);
			case API_PREFIX + "/achievement-diaries":
				requireAllowed(parameters, "region");
				addStrings(arguments, "regions", parameters.get("region"));
				return new Route("achievement-diaries", arguments);
			case API_PREFIX + "/combat-achievements":
				requireAllowed(parameters, "tier", "completed", "query", "offset", "limit");
				addStrings(arguments, "tiers", parameters.get("tier"));
				addBoolean(arguments, "completed", parameters.get("completed"));
				addString(arguments, "query", parameters.get("query"));
				addInteger(arguments, "offset", parameters.get("offset"));
				addInteger(arguments, "limit", parameters.get("limit"));
				return new Route("combat-achievements", arguments);
			case API_PREFIX + "/slayer":
				requireAllowed(parameters, "section");
				addStrings(arguments, "sections", parameters.get("section"));
				return new Route("slayer", arguments);
			case API_PREFIX + "/grand-exchange":
				requireAllowed(parameters);
				return new Route("grand-exchange", arguments);
			case API_PREFIX + "/stored-items":
				requireAllowed(parameters, "container", "query", "item-id", "offset", "limit");
				addStrings(arguments, "containers", parameters.get("container"));
				addString(arguments, "query", parameters.get("query"));
				addInteger(arguments, "itemId", parameters.get("item-id"));
				addInteger(arguments, "offset", parameters.get("offset"));
				addInteger(arguments, "limit", parameters.get("limit"));
				return new Route("stored-items", arguments);
			case API_PREFIX + "/account-wealth":
				requireAllowed(parameters);
				return new Route("account-wealth", arguments);
			case API_PREFIX + "/collection-log":
				requireAllowed(parameters);
				return new Route("collection-log", arguments);
			case API_PREFIX + "/poh":
				requireAllowed(parameters);
				return new Route("poh", arguments);
			case API_PREFIX + "/item-prices":
				requireAllowed(parameters, "id");
				addIntegers(arguments, "itemIds", parameters.get("id"));
				return new Route("item-prices", arguments);
			default:
				return null;
		}
	}

	private static Map<String, List<String>> parseQuery(String rawQuery)
	{
		if (rawQuery == null || rawQuery.isEmpty())
		{
			return Collections.emptyMap();
		}
		Map<String, List<String>> parameters = new HashMap<>();
		for (String pair : rawQuery.split("&", -1))
		{
			int equals = pair.indexOf('=');
			String rawName = equals < 0 ? pair : pair.substring(0, equals);
			String rawValue = equals < 0 ? "" : pair.substring(equals + 1);
			String name = decode(rawName);
			String value = decode(rawValue);
			if (name.isEmpty())
			{
				throw new IllegalArgumentException("Query parameter name must not be empty");
			}
			parameters.computeIfAbsent(name, ignored -> new ArrayList<>()).add(value);
		}
		return parameters;
	}

	private static String decode(String value)
	{
		try
		{
			return URLDecoder.decode(value, StandardCharsets.UTF_8.name());
		}
		catch (IllegalArgumentException ex)
		{
			throw new IllegalArgumentException("Query string contains invalid percent encoding");
		}
		catch (java.io.UnsupportedEncodingException impossible)
		{
			throw new AssertionError(impossible);
		}
	}

	private static void requireNoParameters(String rawQuery)
	{
		if (rawQuery != null && !rawQuery.isEmpty())
		{
			throw new IllegalArgumentException("This endpoint accepts no query parameters");
		}
	}

	private static void requireAllowed(Map<String, List<String>> parameters, String... allowed)
	{
		Set<String> names = new HashSet<>(Arrays.asList(allowed));
		for (String name : parameters.keySet())
		{
			if (!names.contains(name))
			{
				throw new IllegalArgumentException("Unknown query parameter: " + name);
			}
		}
	}

	private static void addString(JsonObject target, String name, List<String> values)
	{
		if (values == null)
		{
			return;
		}
		if (values.size() != 1)
		{
			throw new IllegalArgumentException(name + " must be specified once");
		}
		target.addProperty(name, values.get(0));
	}

	private static void addStrings(JsonObject target, String name, List<String> values)
	{
		if (values == null)
		{
			return;
		}
		JsonArray array = new JsonArray();
		for (String value : values)
		{
			array.add(value);
		}
		target.add(name, array);
	}

	private static void addInteger(JsonObject target, String name, List<String> values)
	{
		if (values == null)
		{
			return;
		}
		if (values.size() != 1)
		{
			throw new IllegalArgumentException(name + " must be specified once");
		}
		target.add(name, integer(values.get(0), name));
	}

	private static void addIntegers(JsonObject target, String name, List<String> values)
	{
		if (values == null)
		{
			return;
		}
		JsonArray array = new JsonArray();
		for (String value : values)
		{
			array.add(integer(value, name));
		}
		target.add(name, array);
	}

	private static JsonPrimitive integer(String value, String name)
	{
		try
		{
			BigDecimal number = new BigDecimal(value);
			number.toBigIntegerExact();
			return new JsonPrimitive(number);
		}
		catch (ArithmeticException | NumberFormatException ex)
		{
			throw new IllegalArgumentException(name + " must be an integer");
		}
	}

	private static void addBoolean(JsonObject target, String name, List<String> values)
	{
		if (values == null)
		{
			return;
		}
		if (values.size() != 1 || !("true".equals(values.get(0)) || "false".equals(values.get(0))))
		{
			throw new IllegalArgumentException(name + " must be true or false");
		}
		target.addProperty(name, Boolean.parseBoolean(values.get(0)));
	}

	private void sendError(HttpExchange exchange, int status, String code, String message) throws IOException
	{
		JsonObject error = new JsonObject();
		error.addProperty("code", code);
		error.addProperty("message", message);
		JsonObject response = new JsonObject();
		response.add("error", error);
		sendJson(exchange, status, gson.toJson(response).getBytes(StandardCharsets.UTF_8));
	}

	private static void sendJson(HttpExchange exchange, int status, byte[] response) throws IOException
	{
		exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
		exchange.getResponseHeaders().set("Cache-Control", "no-store");
		exchange.getResponseHeaders().set("X-Content-Type-Options", "nosniff");
		exchange.sendResponseHeaders(status, response.length);
		exchange.getResponseBody().write(response);
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

	private static byte[] readOpenApi()
	{
		try (InputStream input = QueryHttpServer.class.getResourceAsStream("/openapi.json"))
		{
			if (input == null)
			{
				throw new IllegalStateException("Missing openapi.json resource");
			}
			ByteArrayOutputStream output = new ByteArrayOutputStream();
			byte[] buffer = new byte[8192];
			int read;
			while ((read = input.read(buffer)) != -1)
			{
				output.write(buffer, 0, read);
			}
			return output.toByteArray();
		}
		catch (IOException ex)
		{
			throw new IllegalStateException("Could not read openapi.json", ex);
		}
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

	private static final class Route
	{
		private final String operation;
		private final JsonObject arguments;

		private Route(String operation, JsonObject arguments)
		{
			this.operation = operation;
			this.arguments = arguments;
		}
	}

	private static final class DaemonThreadFactory implements ThreadFactory
	{
		private final AtomicInteger sequence = new AtomicInteger();

		@Override
		public Thread newThread(Runnable runnable)
		{
			Thread thread = new Thread(runnable, "runelite-query-http-" + sequence.incrementAndGet());
			thread.setDaemon(true);
			return thread;
		}
	}
}
