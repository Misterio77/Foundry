package rs.m7.runelitemcp.snapshot;

import com.google.gson.JsonObject;

public interface SnapshotProvider
{
	JsonObject snapshot(SnapshotType type) throws Exception;

	default JsonObject snapshot(SnapshotType type, JsonObject arguments) throws Exception
	{
		return snapshot(type);
	}
}
