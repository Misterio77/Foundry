package rs.m7.runelitemcp.knowledge;

import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import java.io.ByteArrayOutputStream;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Flow;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.locks.ReentrantLock;
import javax.inject.Inject;
import javax.inject.Singleton;
import rs.m7.runelitemcp.RuneLiteMcpConfig;

@Singleton
public final class OsrsWikiClient implements WikiProvider
{
	private static final String USER_AGENT = "RuneLite-MCP/0.1.0 (https://github.com/misterio77/Foundry)";
	private static final int MAX_RESPONSE_BYTES = 1024 * 1024;
	private static final int MAX_CACHE_ENTRIES = 64;
	private static final long CACHE_NANOS = TimeUnit.MINUTES.toNanos(10);
	private static final long REQUEST_INTERVAL_NANOS = TimeUnit.SECONDS.toNanos(1);

	private final RuneLiteMcpConfig config;
	private final Boolean forcedEnabled;
	private final Gson gson;
	private final URI endpoint;
	private final HttpClient http;
	private final ReentrantLock requestLock = new ReentrantLock();
	private final AtomicLong lifecycleGeneration = new AtomicLong();
	private final AtomicReference<CompletableFuture<?>> activeRequest = new AtomicReference<>();
	private final Map<String, CacheEntry> cache = new LinkedHashMap<String, CacheEntry>(16, 0.75F, true)
	{
		@Override
		protected boolean removeEldestEntry(Map.Entry<String, CacheEntry> eldest)
		{
			return size() > MAX_CACHE_ENTRIES;
		}
	};
	private long lastRequestNanos;

	@Inject
	public OsrsWikiClient(RuneLiteMcpConfig config, Gson gson)
	{
		this.config = config;
		this.forcedEnabled = null;
		this.gson = gson;
		this.endpoint = URI.create("https://oldschool.runescape.wiki/api.php");
		this.http = httpClient();
	}

	OsrsWikiClient(boolean enabled, Gson gson, URI endpoint)
	{
		this.config = null;
		this.forcedEnabled = enabled;
		this.gson = gson;
		this.endpoint = endpoint;
		this.http = httpClient();
	}

	private static HttpClient httpClient()
	{
		return HttpClient.newBuilder()
			.connectTimeout(Duration.ofSeconds(3))
			.followRedirects(HttpClient.Redirect.NEVER)
			.build();
	}

	@Override
	public boolean isEnabled()
	{
		return forcedEnabled != null ? forcedEnabled : config.wikiAccess();
	}

	@Override
	public JsonObject search(String query, int limit) throws Exception
	{
		ensureEnabled();
		String key = "search:" + limit + ":" + query;
		JsonObject cached = cached(key);
		if (cached != null)
		{
			return cached;
		}
		String parameters = "action=query&list=search&format=json&formatversion=2&srprop=wordcount%7Ctimestamp"
			+ "&srlimit=" + limit + "&srsearch=" + encode(query);
		JsonObject response = request(parameters);
		long requestGeneration = response.remove("_lifecycleGeneration").getAsLong();
		if (!response.has("query") || !response.get("query").isJsonObject()
			|| !response.getAsJsonObject("query").has("search")
			|| !response.getAsJsonObject("query").get("search").isJsonArray())
		{
			throw new IllegalStateException("OSRS Wiki returned an unexpected search response");
		}
		JsonArray results = new JsonArray();
		for (JsonElement element : response.getAsJsonObject("query").getAsJsonArray("search"))
		{
			if (results.size() >= limit)
			{
				break;
			}
			if (!element.isJsonObject())
			{
				throw new IllegalStateException("OSRS Wiki returned an unexpected search entry");
			}
			JsonObject source = element.getAsJsonObject();
			if (!positiveNumber(source, "pageid") || !nonnegativeNumber(source, "wordcount")
				|| !boundedString(source, "title", 256) || !boundedString(source, "timestamp", 64))
			{
				throw new IllegalStateException("OSRS Wiki returned an incomplete or oversized search entry");
			}
			JsonObject result = new JsonObject();
			result.addProperty("pageId", source.get("pageid").getAsLong());
			result.addProperty("title", source.get("title").getAsString());
			result.addProperty("wordCount", source.get("wordcount").getAsInt());
			result.addProperty("timestamp", source.get("timestamp").getAsString());
			results.add(result);
		}
		JsonObject value = new JsonObject();
		value.addProperty("source", "OSRS Wiki");
		value.addProperty("query", query);
		value.addProperty("cached", false);
		value.add("results", results);
		put(key, value, requestGeneration);
		return value.deepCopy();
	}

	@Override
	public JsonObject page(String title, int maxCharacters) throws Exception
	{
		ensureEnabled();
		String key = "page:" + maxCharacters + ":" + title;
		JsonObject cached = cached(key);
		if (cached != null)
		{
			return cached;
		}
		String parameters = "action=query&prop=extracts&explaintext=1&redirects=1&format=json&formatversion=2"
			+ "&titles=" + encode(title);
		JsonObject response = request(parameters);
		long requestGeneration = response.remove("_lifecycleGeneration").getAsLong();
		if (!response.has("query") || !response.get("query").isJsonObject()
			|| !response.getAsJsonObject("query").has("pages")
			|| !response.getAsJsonObject("query").get("pages").isJsonArray())
		{
			throw new IllegalStateException("OSRS Wiki returned an unexpected page response");
		}
		JsonArray pages = response.getAsJsonObject("query").getAsJsonArray("pages");
		if (pages.size() != 1 || !pages.get(0).isJsonObject()
			|| pages.get(0).getAsJsonObject().has("missing"))
		{
			throw new IllegalArgumentException("OSRS Wiki page was not found");
		}
		JsonObject source = pages.get(0).getAsJsonObject();
		if (!positiveNumber(source, "pageid") || !boundedString(source, "title", 256))
		{
			throw new IllegalStateException("OSRS Wiki returned an incomplete page response");
		}
		String extract = source.has("extract") && !source.get("extract").isJsonNull()
			&& source.get("extract").isJsonPrimitive() && source.getAsJsonPrimitive("extract").isString()
			? source.get("extract").getAsString() : "";
		int codePoints = extract.codePointCount(0, extract.length());
		boolean truncated = codePoints > maxCharacters;
		if (truncated)
		{
			extract = extract.substring(0, extract.offsetByCodePoints(0, maxCharacters));
		}
		JsonObject value = new JsonObject();
		value.addProperty("source", "OSRS Wiki");
		value.addProperty("pageId", source.get("pageid").getAsLong());
		value.addProperty("title", source.get("title").getAsString());
		value.addProperty("text", extract);
		value.addProperty("truncated", truncated);
		value.addProperty("maxCharacters", maxCharacters);
		value.addProperty("cached", false);
		put(key, value, requestGeneration);
		return value.deepCopy();
	}

	private JsonObject request(String parameters) throws Exception
	{
		if (!requestLock.tryLock())
		{
			throw new IllegalStateException("Another OSRS Wiki request is already in progress");
		}
		long requestGeneration = lifecycleGeneration.get();
		long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(6);
		try
		{
			long wait = REQUEST_INTERVAL_NANOS - (System.nanoTime() - lastRequestNanos);
			if (lastRequestNanos != 0 && wait > 0)
			{
				TimeUnit.NANOSECONDS.sleep(wait);
			}
			ensureEnabled();
			lastRequestNanos = System.nanoTime();
			HttpRequest request = HttpRequest.newBuilder(URI.create(endpoint + "?" + parameters))
				.timeout(Duration.ofSeconds(5))
				.header("Accept", "application/json")
				.header("User-Agent", USER_AGENT)
				.GET()
				.build();
			CompletableFuture<HttpResponse<byte[]>> future = http.sendAsync(request,
				responseInfo -> new BoundedBodySubscriber());
			activeRequest.set(future);
			if (requestGeneration != lifecycleGeneration.get() || !isEnabled())
			{
				future.cancel(true);
				throw new IllegalStateException("OSRS Wiki request was invalidated before sending");
			}
			final HttpResponse<byte[]> response;
			try
			{
				long remaining = deadline - System.nanoTime();
				if (remaining <= 0)
				{
					future.cancel(true);
					throw new IllegalStateException("OSRS Wiki response timed out");
				}
				response = future.get(remaining, TimeUnit.NANOSECONDS);
			}
			catch (TimeoutException ex)
			{
				future.cancel(true);
				throw new IllegalStateException("OSRS Wiki response timed out");
			}
			if (response.statusCode() != 200)
			{
				throw new IllegalStateException("OSRS Wiki returned HTTP " + response.statusCode());
			}
			String contentType = response.headers().firstValue("Content-Type").orElse("");
			if (!contentType.toLowerCase(java.util.Locale.ROOT).startsWith("application/json"))
			{
				throw new IllegalStateException("OSRS Wiki returned a non-JSON response");
			}
			JsonObject value = gson.fromJson(new String(response.body(), StandardCharsets.UTF_8), JsonObject.class);
			if (requestGeneration != lifecycleGeneration.get() || !isEnabled())
			{
				throw new IllegalStateException("OSRS Wiki request was invalidated by shutdown or configuration change");
			}
			if (value == null || value.has("error"))
			{
				throw new IllegalStateException("OSRS Wiki returned an API error");
			}
			value.addProperty("_lifecycleGeneration", requestGeneration);
			return value;
		}
		finally
		{
			activeRequest.set(null);
			requestLock.unlock();
		}
	}

	public synchronized void clear()
	{
		lifecycleGeneration.incrementAndGet();
		CompletableFuture<?> request = activeRequest.getAndSet(null);
		if (request != null)
		{
			request.cancel(true);
		}
		cache.clear();
	}

	private synchronized JsonObject cached(String key)
	{
		CacheEntry entry = cache.get(key);
		if (entry == null || System.nanoTime() >= entry.expiresAtNanos)
		{
			cache.remove(key);
			return null;
		}
		JsonObject value = entry.value.deepCopy();
		value.addProperty("cached", true);
		return value;
	}

	private synchronized void put(String key, JsonObject value, long requestGeneration)
	{
		if (requestGeneration != lifecycleGeneration.get() || !isEnabled())
		{
			throw new IllegalStateException("OSRS Wiki response was invalidated before caching");
		}
		cache.put(key, new CacheEntry(value.deepCopy(), System.nanoTime() + CACHE_NANOS));
	}

	private static boolean positiveNumber(JsonObject object, String name)
	{
		return integerSign(object, name) > 0;
	}

	private static boolean nonnegativeNumber(JsonObject object, String name)
	{
		return integerSign(object, name) >= 0;
	}

	private static int integerSign(JsonObject object, String name)
	{
		if (!object.has(name) || !object.get(name).isJsonPrimitive()
			|| !object.getAsJsonPrimitive(name).isNumber())
		{
			return -1;
		}
		try
		{
			return new java.math.BigDecimal(object.get(name).getAsString()).toBigIntegerExact().signum();
		}
		catch (ArithmeticException | NumberFormatException ex)
		{
			return -1;
		}
	}

	private static boolean boundedString(JsonObject object, String name, int maximum)
	{
		return object.has(name) && object.get(name).isJsonPrimitive()
			&& object.getAsJsonPrimitive(name).isString()
			&& object.get(name).getAsString().length() <= maximum;
	}

	private void ensureEnabled()
	{
		if (!isEnabled())
		{
			throw new IllegalStateException("OSRS Wiki access is disabled in RuneLite MCP settings");
		}
	}

	private static String encode(String value)
	{
		return URLEncoder.encode(value, StandardCharsets.UTF_8);
	}

	private static final class BoundedBodySubscriber implements HttpResponse.BodySubscriber<byte[]>
	{
		private final CompletableFuture<byte[]> body = new CompletableFuture<>();
		private final ByteArrayOutputStream output = new ByteArrayOutputStream();
		private Flow.Subscription subscription;
		private int size;

		@Override
		public CompletableFuture<byte[]> getBody()
		{
			return body;
		}

		@Override
		public void onSubscribe(Flow.Subscription subscription)
		{
			this.subscription = subscription;
			subscription.request(Long.MAX_VALUE);
		}

		@Override
		public void onNext(List<ByteBuffer> buffers)
		{
			for (ByteBuffer buffer : buffers)
			{
				int remaining = buffer.remaining();
				size += remaining;
				if (size > MAX_RESPONSE_BYTES)
				{
					subscription.cancel();
					body.completeExceptionally(new IllegalStateException(
						"OSRS Wiki response exceeded the size limit"));
					return;
				}
				byte[] bytes = new byte[remaining];
				buffer.get(bytes);
				output.write(bytes, 0, bytes.length);
			}
		}

		@Override
		public void onError(Throwable throwable)
		{
			body.completeExceptionally(throwable);
		}

		@Override
		public void onComplete()
		{
			body.complete(output.toByteArray());
		}
	}

	private static final class CacheEntry
	{
		private final JsonObject value;
		private final long expiresAtNanos;

		private CacheEntry(JsonObject value, long expiresAtNanos)
		{
			this.value = value;
			this.expiresAtNanos = expiresAtNanos;
		}
	}
}
