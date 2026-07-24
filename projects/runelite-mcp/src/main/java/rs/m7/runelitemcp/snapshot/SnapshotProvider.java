package rs.m7.runelitemcp.snapshot;

import com.google.gson.JsonObject;

public interface SnapshotProvider
{
	JsonObject snapshot() throws Exception;
}
