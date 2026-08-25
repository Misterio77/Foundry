package rs.m7.runelitequery;

import net.runelite.client.RuneLite;
import net.runelite.client.externalplugins.ExternalPluginManager;

public class RuneLiteQueryPluginTest
{
	public static void main(String[] args) throws Exception
	{
		ExternalPluginManager.loadBuiltin(RuneLiteQueryPlugin.class);
		RuneLite.main(args);
	}
}
