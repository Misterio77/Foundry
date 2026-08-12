{config, lib, ...}: let
  realName = "Gabriel Fontes";
  address = "g.fontes@usp.br";

  commonChannelCfg = {
    Expunge = "Both"; # Sync deleted messages
    Create = "Both"; # Create mailboxes if needed
    Remove = "None"; # Don't ever delete mailboxes
    SyncState = "*"; # Ensure sync state is in mail dir
  };
  gmailChannels = {
    Inbox = {
      farPattern = "INBOX";
      nearPattern = "Inbox";
      extraConfig = commonChannelCfg;
    };
    Archive = {
      farPattern = "Archived Mail";
      nearPattern = "Archive";
      extraConfig = commonChannelCfg;
    };
    Junk = {
      farPattern = "[Gmail]/Spam";
      nearPattern = "Junk";
      extraConfig = commonChannelCfg;
    };
    Trash = {
      farPattern = "[Gmail]/Trash";
      nearPattern = "Trash";
      extraConfig = commonChannelCfg;
    };
    Drafts = {
      farPattern = "[Gmail]/Drafts";
      nearPattern = "Drafts";
      extraConfig = commonChannelCfg;
    };
    Sent = {
      farPattern = "[Gmail]/Sent Mail";
      nearPattern = "Sent";
      extraConfig = commonChannelCfg;
    };
  };

  oama = lib.getExe config.programs.oama.package;
in {
  accounts = {
    email.accounts.usp = {
      inherit address realName;
      signature = {
        showSignature = "append";
        text = ''
          ${realName}

          Master's Student
          University of São Paulo, Brazil

          https://gsfontes.com
        '';
      };

      flavor = "gmail.com";
      userName = address;
      passwordCommand = "${oama} access ${address}";

      mbsync = {
        enable = true;
        groups.usp.channels = gmailChannels;
        extraConfig = {
          channel = commonChannelCfg; # TODO: check if I really need this one
          account.AuthMechs = "XOAUTH2";
        };
      };
      msmtp = {
        extraConfig.auth = "oauthbearer";
        enable = true;
      };
      neomutt = {
        enable = true;
        mailboxName = "=== USP ===";
        extraMailboxes = [
          "Archive"
          "Drafts"
          "Junk"
          "Sent"
          "Trash"
        ];
        # Gmail already stores a copy
        extraConfig = ''
          set copy = no
        '';
      };
      aerc = {
        enable = true;
        # Pinned at the top of the sidebar, in this order; the rest stays
        # alphabetical
        extraAccounts.folders-sort = [
          "Inbox"
          "Archive"
          "Drafts"
          "Sent"
          "Junk"
          "Trash"
        ];
      };
    };

    calendar.accounts.usp = {
      primaryCollection = address;
      khal = {
        enable = true;
        addresses = [address];
        type = "discover";
      };
      remote = {
        type = "google_calendar";
      };
      vdirsyncer = {
        enable = true;
        metadata = ["color" "displayname"];
        collections = ["from a" "from b"];
        accessTokenCommand = [oama "access" address];
      };
    };
  };
}
