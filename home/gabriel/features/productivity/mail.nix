{
  pkgs,
  lib,
  config,
  ...
}: let
  pass = "${config.programs.password-store.package}/bin/pass";
  oama = "${config.programs.oama.package}/bin/oama";

  common = rec {
    realName = "Gabriel Fontes";
    gpg = {
      key = "7088 C742 1873 E0DB 97FF 17C2 245C AB70 B4C2 25E9";
      signByDefault = false;
    };
    signature = {
      showSignature = "append";
      text = ''
        ${realName}

        https://gsfontes.com
      '';
    };
  };

  commonChannelCfg = {
    Expunge = "Both"; # Sync deleted messages
    Create = "Both"; # Create mailboxes if needed
    Remove = "None"; # Don't ever delete mailboxes
    SyncState = "*"; # Ensure sync state is in mail dir
  };

  gmail_channels = {
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
in {
  home.persistence = {
    "/persist".directories = ["Mail"];
  };

  accounts.email = {
    maildirBasePath = "Mail";
    accounts = {
      personal =
        rec {
          primary = true;
          address = "hi@m7.rs";
          aliases = [
            "gabriel@gsfontes.com"
            "eu@misterio.me"
          ];
          userName = address;
          passwordCommand = "${pass} ${smtp.host}/${address}";

          imap.host = "mail.m7.rs";
          mbsync = {
            enable = true;
            extraConfig.channel = commonChannelCfg;
          };
          neomutt = {
            enable = true;
            mailboxName = "=== Personal ===";
            extraMailboxes = [
              "Archive"
              "Drafts"
              "Junk"
              "Sent"
              "Trash"
            ];
          };

          msmtp.enable = true;
          smtp.host = "mail.m7.rs";
        }
        // common;

      usp =
        rec {
          address = "g.fontes@usp.br";
          userName = address;
          passwordCommand = "${oama} access ${address}";
          flavor = "gmail.com";

          mbsync = {
            enable = true;
            groups.usp.channels = gmail_channels;
            extraConfig.channel = commonChannelCfg;
            extraConfig.account.AuthMechs = "XOAUTH2";
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

          msmtp = {
            extraConfig.auth = "oauthbearer";
            enable = true;
          };
        }
        // common;
    };
  };

  programs.msmtp.enable = true;
  programs.mbsync = {
    enable = true;
    package = pkgs.isync.override {
      withCyrusSaslXoauth2 = true;
    };
  };

  services.mbsync = {
    enable = true;
    package = config.programs.mbsync.package;
  };

  # Only run if gpg is unlocked
  systemd.user.services.mbsync.Service.ExecCondition = let
    gpgCmds = import ../cli/gpg-commands.nix {inherit pkgs config lib;};
  in ''
    /bin/sh -c "${gpgCmds.isUnlocked}"
  '';

  # Ensure 'createMaildir' runs after 'linkGeneration'
  home.activation = {
    createMaildir = lib.mkForce (lib.hm.dag.entryAfter ["linkGeneration"] ''
      run mkdir -m700 -p $VERBOSE_ARG ${
        lib.concatStringsSep " " (lib.mapAttrsToList (_: v: v.maildir.absPath) config.accounts.email.accounts)
      }
    '');
  };
}
