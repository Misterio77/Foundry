package rs.m7.runelitemcp;

import net.runelite.client.RuneLite;
import net.runelite.client.externalplugins.ExternalPluginManager;

public class RuneLiteMcpPluginTest
{
	public static void main(String[] args) throws Exception
	{
		ExternalPluginManager.loadBuiltin(RuneLiteMcpPlugin.class);
		RuneLite.main(args);
	}
}
