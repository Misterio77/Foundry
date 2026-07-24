package rs.m7.runelitemcp.knowledge;

import com.google.gson.JsonObject;

public interface WikiProvider
{
	boolean isEnabled();

	JsonObject search(String query, int limit) throws Exception;

	JsonObject page(String title, int maxCharacters) throws Exception;
}
