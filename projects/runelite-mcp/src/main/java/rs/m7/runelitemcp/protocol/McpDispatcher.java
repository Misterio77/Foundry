package rs.m7.runelitemcp.protocol;

import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import com.google.gson.JsonParseException;
import com.google.gson.JsonParser;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;
import rs.m7.runelitemcp.snapshot.SnapshotProvider;

public class McpDispatcher
{
	static final String PROTOCOL_VERSION = "2025-11-25";

	private final SnapshotProvider snapshots;
	private final Gson gson;

	public McpDispatcher(SnapshotProvider snapshots, Gson gson)
	{
		this.snapshots = snapshots;
		this.gson = gson.newBuilder().serializeNulls().create();
	}

	public DispatchResult dispatch(String body)
	{
		final JsonObject request;
		try
		{
			JsonElement parsed = new JsonParser().parse(body);
			if (!parsed.isJsonObject())
			{
				return error(JsonNull.INSTANCE, -32600, "Request must be a JSON object");
			}
			request = parsed.getAsJsonObject();
		}
		catch (JsonParseException ex)
		{
			return error(JsonNull.INSTANCE, -32700, "Invalid JSON");
		}

		JsonElement id = request.has("id") ? request.get("id") : null;
		if (!validId(id))
		{
			return error(JsonNull.INSTANCE, -32600, "JSON-RPC id must be a string, number, or null");
		}
		if (!request.has("jsonrpc") || !"2.0".equals(string(request.get("jsonrpc")))
			|| !request.has("method") || !request.get("method").isJsonPrimitive()
			|| !request.getAsJsonPrimitive("method").isString())
		{
			return error(idOrNull(id), -32600, "Invalid JSON-RPC request");
		}

		String method = request.get("method").getAsString();
		boolean notification = id == null;
		try
		{
			if (request.has("params") && !request.get("params").isJsonObject())
			{
				throw new IllegalArgumentException("params must be an object");
			}
			JsonObject params = request.has("params")
				? request.getAsJsonObject("params")
				: new JsonObject();
			JsonElement result = handle(method, params);
			if (notification)
			{
				return DispatchResult.accepted();
			}
			if (result == null)
			{
				return error(idOrNull(id), -32601, "Method not found");
			}
			return success(idOrNull(id), result);
		}
		catch (IllegalArgumentException ex)
		{
			return notification ? DispatchResult.accepted() : error(idOrNull(id), -32602, ex.getMessage());
		}
		catch (Exception ex)
		{
			return notification ? DispatchResult.accepted() : error(idOrNull(id), -32603, "RuneLite MCP request failed");
		}
	}

	private JsonElement handle(String method, JsonObject params) throws Exception
	{
		switch (method)
		{
			case "initialize":
				return initialize(params);
			case "ping":
				return new JsonObject();
			case "tools/list":
				return toolsList();
			case "tools/call":
				return callTool(params);
			case "resources/list":
				return resourcesList();
			case "resources/read":
				return readResource(params);
			case "prompts/list":
				return promptsList();
			case "prompts/get":
				return getPrompt(params);
			default:
				return null;
		}
	}

	private JsonObject initialize(JsonObject params)
	{
		String requestedVersion = requiredString(params, "protocolVersion");
		if (!PROTOCOL_VERSION.equals(requestedVersion))
		{
			throw new IllegalArgumentException("Unsupported MCP protocol version; expected " + PROTOCOL_VERSION);
		}
		requiredObject(params, "capabilities");
		JsonObject clientInfo = requiredObject(params, "clientInfo");
		requiredString(clientInfo, "name");
		requiredString(clientInfo, "version");

		JsonObject capabilities = new JsonObject();
		capabilities.add("tools", new JsonObject());
		capabilities.add("resources", new JsonObject());
		capabilities.add("prompts", new JsonObject());

		JsonObject serverInfo = new JsonObject();
		serverInfo.addProperty("name", "runelite-mcp");
		serverInfo.addProperty("version", "0.1.0");

		JsonObject result = new JsonObject();
		result.addProperty("protocolVersion", PROTOCOL_VERSION);
		result.add("capabilities", capabilities);
		result.add("serverInfo", serverInfo);
		result.addProperty("instructions", "Live informational RuneLite data. Tools never perform game actions.");
		return result;
	}

	private JsonObject toolsList()
	{
		JsonArray tools = new JsonArray();
		tools.add(tool(
			"get_game_context",
			"Read a current RuneLite session and player snapshot, including location, movement, interaction, and core vitals. Returns active, loading, or logged_out state and never controls gameplay.",
			"{\"type\":\"object\",\"properties\":{},\"additionalProperties\":false}"
		));
		tools.add(tool(
			"skills",
			"Read current real and boosted skill levels and XP. Omit the names argument to return every skill.",
			"{\"type\":\"object\",\"properties\":{\"names\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}},\"additionalProperties\":false}"
		));

		JsonObject result = new JsonObject();
		result.add("tools", tools);
		return result;
	}

	private JsonObject callTool(JsonObject params) throws Exception
	{
		String name = requiredString(params, "name");
		JsonObject arguments = new JsonObject();
		if (params.has("arguments"))
		{
			if (!params.get("arguments").isJsonObject())
			{
				throw new IllegalArgumentException("arguments must be an object");
			}
			arguments = params.getAsJsonObject("arguments");
		}

		switch (name)
		{
			case "get_game_context":
				rejectUnknownArguments(arguments);
				return toolResult(gameContext(snapshots.snapshot()));
			case "skills":
				rejectUnknownArguments(arguments, "names");
				return toolResult(skills(snapshots.snapshot(), arguments));
			default:
				return toolError("Unknown tool: " + name);
		}
	}

	private static JsonObject gameContext(JsonObject snapshot)
	{
		JsonObject context = snapshot.deepCopy();
		context.remove("skills");
		return context;
	}

	private JsonObject skills(JsonObject snapshot, JsonObject arguments)
	{
		Set<String> names = new HashSet<>();
		if (arguments.has("names"))
		{
			if (!arguments.get("names").isJsonArray())
			{
				throw new IllegalArgumentException("names must be an array of strings");
			}
			for (JsonElement name : arguments.getAsJsonArray("names"))
			{
				if (!name.isJsonPrimitive() || !name.getAsJsonPrimitive().isString())
				{
					throw new IllegalArgumentException("names must be an array of strings");
				}
				names.add(name.getAsString().toLowerCase(Locale.ROOT));
			}
		}

		JsonArray filtered = new JsonArray();
		for (JsonElement skill : snapshot.getAsJsonArray("skills"))
		{
			String name = skill.getAsJsonObject().get("name").getAsString();
			if (names.isEmpty() || names.contains(name.toLowerCase(Locale.ROOT)))
			{
				filtered.add(skill.deepCopy());
			}
		}

		JsonObject result = new JsonObject();
		result.add("state", snapshot.get("state").deepCopy());
		result.add("sample", snapshot.get("sample").deepCopy());
		result.add("skills", filtered);
		return result;
	}

	private JsonObject resourcesList()
	{
		JsonObject resource = new JsonObject();
		resource.addProperty("uri", "runelite://game/context");
		resource.addProperty("name", "RuneLite game context");
		resource.addProperty("description", "Current informational session and local-player snapshot");
		resource.addProperty("mimeType", "application/json");

		JsonArray resources = new JsonArray();
		resources.add(resource);
		JsonObject result = new JsonObject();
		result.add("resources", resources);
		return result;
	}

	private JsonObject readResource(JsonObject params) throws Exception
	{
		String uri = requiredString(params, "uri");
		if (!"runelite://game/context".equals(uri))
		{
			throw new IllegalArgumentException("Unknown resource URI: " + uri);
		}

		JsonObject content = new JsonObject();
		content.addProperty("uri", uri);
		content.addProperty("mimeType", "application/json");
		content.addProperty("text", gson.toJson(gameContext(snapshots.snapshot())));
		JsonArray contents = new JsonArray();
		contents.add(content);
		JsonObject result = new JsonObject();
		result.add("contents", contents);
		return result;
	}

	private JsonObject promptsList()
	{
		JsonObject prompt = new JsonObject();
		prompt.addProperty("name", "osrs_session_brief");
		prompt.addProperty("description", "Begin an OSRS assistance session from current RuneLite state");
		JsonArray prompts = new JsonArray();
		prompts.add(prompt);
		JsonObject result = new JsonObject();
		result.add("prompts", prompts);
		return result;
	}

	private JsonObject getPrompt(JsonObject params)
	{
		String name = requiredString(params, "name");
		if (!"osrs_session_brief".equals(name))
		{
			throw new IllegalArgumentException("Unknown prompt: " + name);
		}

		JsonObject text = new JsonObject();
		text.addProperty("type", "text");
		text.addProperty("text", "Call get_game_context, summarize the current session, and ask what help is wanted. Treat RuneLite state as observational only and never claim to perform gameplay actions.");
		JsonObject message = new JsonObject();
		message.addProperty("role", "user");
		message.add("content", text);
		JsonArray messages = new JsonArray();
		messages.add(message);
		JsonObject result = new JsonObject();
		result.addProperty("description", "Start from live RuneLite context");
		result.add("messages", messages);
		return result;
	}

	private static JsonObject tool(String name, String description, String schema)
	{
		JsonObject tool = new JsonObject();
		tool.addProperty("name", name);
		tool.addProperty("description", description);
		tool.add("inputSchema", new JsonParser().parse(schema));
		JsonObject annotations = new JsonObject();
		annotations.addProperty("readOnlyHint", true);
		annotations.addProperty("destructiveHint", false);
		annotations.addProperty("idempotentHint", true);
		annotations.addProperty("openWorldHint", false);
		tool.add("annotations", annotations);
		return tool;
	}

	private JsonObject toolResult(JsonElement data)
	{
		JsonObject text = new JsonObject();
		text.addProperty("type", "text");
		text.addProperty("text", gson.toJson(data));
		JsonArray content = new JsonArray();
		content.add(text);
		JsonObject result = new JsonObject();
		result.add("content", content);
		result.add("structuredContent", data);
		return result;
	}

	private JsonObject toolError(String message)
	{
		JsonObject result = toolResult(new JsonParser().parse("{\"error\":" + gson.toJson(message) + "}"));
		result.addProperty("isError", true);
		return result;
	}

	private DispatchResult success(JsonElement id, JsonElement result)
	{
		JsonObject response = new JsonObject();
		response.addProperty("jsonrpc", "2.0");
		response.add("id", id.deepCopy());
		response.add("result", result);
		return DispatchResult.json(gson.toJson(response));
	}

	private DispatchResult error(JsonElement id, int code, String message)
	{
		JsonObject details = new JsonObject();
		details.addProperty("code", code);
		details.addProperty("message", message);
		JsonObject response = new JsonObject();
		response.addProperty("jsonrpc", "2.0");
		response.add("id", id.deepCopy());
		response.add("error", details);
		return DispatchResult.json(gson.toJson(response));
	}

	private static JsonElement idOrNull(JsonElement id)
	{
		return id == null ? JsonNull.INSTANCE : id;
	}

	private static boolean validId(JsonElement id)
	{
		return id == null || id.isJsonNull()
			|| id.isJsonPrimitive() && (id.getAsJsonPrimitive().isString() || id.getAsJsonPrimitive().isNumber());
	}

	private static void rejectUnknownArguments(JsonObject arguments, String... allowed)
	{
		Set<String> names = new HashSet<>();
		for (String name : allowed)
		{
			names.add(name);
		}
		for (String name : arguments.keySet())
		{
			if (!names.contains(name))
			{
				throw new IllegalArgumentException("Unknown argument: " + name);
			}
		}
	}

	private static String requiredString(JsonObject object, String name)
	{
		if (!object.has(name) || !object.get(name).isJsonPrimitive() || !object.getAsJsonPrimitive(name).isString())
		{
			throw new IllegalArgumentException(name + " must be a string");
		}
		return object.get(name).getAsString();
	}

	private static JsonObject requiredObject(JsonObject object, String name)
	{
		if (!object.has(name) || !object.get(name).isJsonObject())
		{
			throw new IllegalArgumentException(name + " must be an object");
		}
		return object.getAsJsonObject(name);
	}

	private static String string(JsonElement value)
	{
		return value != null && value.isJsonPrimitive() ? value.getAsString() : null;
	}

}
