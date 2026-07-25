package rs.m7.runelitemcp;

import net.runelite.api.MenuAction;
import net.runelite.api.gameval.InterfaceID;
import net.runelite.api.gameval.ItemID;
import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

@SuppressWarnings("deprecation")
public class RuneLiteMcpPluginUnitTest
{
	@Test
	public void recognizesOnlySelfHouseEntryActions()
	{
		assertEquals("teleport_to_house_spell", RuneLiteMcpPlugin.selfPohEntryEvidence(
			InterfaceID.MagicSpellbook.TELEPORT_TO_YOUR_HOUSE, "Cast", null,
			-1, MenuAction.CC_OP));
		assertNull(RuneLiteMcpPlugin.selfPohEntryEvidence(
			InterfaceID.MagicSpellbook.TELEPORT_TO_YOUR_HOUSE, "Outside", null,
			-1, MenuAction.CC_OP));
		assertEquals("house_teleport_tablet", RuneLiteMcpPlugin.selfPohEntryEvidence(
			-1, "Break", null, ItemID.POH_TABLET_TELEPORTTOHOUSE,
			MenuAction.ITEM_FIRST_OPTION));
		assertNull(RuneLiteMcpPlugin.selfPohEntryEvidence(
			-1, "Outside", null, ItemID.POH_TABLET_TELEPORTTOHOUSE,
			MenuAction.ITEM_SECOND_OPTION));
		assertEquals("house_portal_home_option", RuneLiteMcpPlugin.selfPohEntryEvidence(
			-1, "Home", "<col=ffff>Portal</col>", -1,
			MenuAction.GAME_OBJECT_SECOND_OPTION));
	}
}
