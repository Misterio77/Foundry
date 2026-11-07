{
  config,
  lib,
  pkgs,
  ...
}: let
  realName = "Gabriel Fontes";
  address = "hi@m7.rs";
  aliases = ["gabriel@gsfontes.com" "eu@misterio.me"];
  mailHost = "mail.m7.rs";
  davHost = "dav.m7.rs";

  oama = lib.getExe config.programs.oama.package;
  flock = lib.getExe' pkgs.util-linux "flock";
  accessTokenCommand = ''${flock} "$XDG_RUNTIME_DIR/oama-personal.lock" ${oama} access ${address}'';
in {
  programs.oama.settings.services.gablogin = {
    client_id = "mail-and-dav";
    auth_endpoint = "https://auth.m7.rs/application/o/authorize/";
    auth_http_method = "GET";
    token_endpoint = "https://auth.m7.rs/application/o/token/";
    token_params_mode = "RequestBodyForm";
    redirect_uri = "http://127.0.0.1:8765/callback";
    auth_scope = "openid profile offline_access urn:ietf:params:oauth:scope:mail ak_proxy";
  };

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
      passwordCommand = accessTokenCommand;
      imap.host = mailHost;
      smtp.host = mailHost;

      mbsync = {
        enable = true;
        extraConfig = {
          account.AuthMechs = "XOAUTH2";
          channel = {
            Expunge = "Both";
            Create = "Both";
            Remove = "None";
            SyncState = "*";
          };
        };
      };
      msmtp = {
        enable = true;
        extraConfig.auth = "oauthbearer";
      };
      aerc = {
        enable = true;
        extraAccounts.restrict-delete = true;
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

    contact.accounts.personal = {
      # Keep the existing flat address-book layout used by khard.
      local.path = config.accounts.contact.basePath;
      remote = {
        type = "carddav";
        url = "https://${davHost}";
      };
      vdirsyncer = {
        enable = true;
        collections = ["Main"];
        tokenCommand = [pkgs.runtimeShell "-c" accessTokenCommand];
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
      };
      vdirsyncer = {
        enable = true;
        metadata = ["color" "displayname"];
        tokenCommand = [pkgs.runtimeShell "-c" accessTokenCommand];
        collections = [
          "Personal"
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
