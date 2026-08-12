{
  config,
  lib,
  ...
}: let
  realName = "Gabriel Fontes";
  address = "hi@m7.rs";
  aliases = ["gabriel@gsfontes.com" "eu@misterio.me"];
  mailHost = "mail.m7.rs";
  davHost = "dav.m7.rs";

  pass = lib.getExe config.programs.password-store.package;
in {
  accounts = {
    email.accounts.personal = {
      inherit address realName aliases;
      signature = {
        showSignature = "append";
        text = ''
          ${realName}

          https://gsfontes.com
        '';
      };

      userName = address;
      passwordCommand = "${pass} ${mailHost}/${address}";
      imap.host = mailHost;
      smtp.host = mailHost;

      mbsync = {
        enable = true;
        extraConfig.channel = {
          Expunge = "Both"; # Sync deleted messages
          Create = "Both"; # Create mailboxes if needed
          Remove = "None"; # Don't ever delete mailboxes
          SyncState = "*"; # Ensure sync state is in mail dir
        };
      };
      msmtp = {
        enable = true;
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

    calendar.accounts.personal = {
      primaryCollection = "Personal";
      khal = {
        enable = true;
        addresses = [address] ++ aliases;
        type = "discover";
      };
      remote = {
        type = "caldav";
        url = "https://${davHost}";
        userName = address;
        passwordCommand = [pass "${mailHost}/${address}"];
      };
      vdirsyncer = {
        enable = true;
        metadata = ["color" "displayname"];
        collections = [
          "Personal"
          "projects"
          "ideas"
          "reading-list"
          "routine"
          "7eebf97d-5962-5fcd-4e73-888f22720cee" # Casa
          "Postgrad"
          "GELOS"
          "29c5b864-a7b9-4130-bed3-8fb7a9c3d331" # Lumis
          "3ce52be8-d87e-4b4d-8225-a9c65840c72e" # Magalu
        ];
      };
    };
  };
}
