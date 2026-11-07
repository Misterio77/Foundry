{
  config,
  lib,
  ...
}: let
  address = "contato@lumis.cards";
  mailHost = "mail.lumis.cards";
  oama = lib.getExe config.programs.oama.package;
in {
  programs.oama.settings.services.gablogin = {
    client_id = "stalwart";
    auth_endpoint = "https://auth.m7.rs/application/o/authorize/";
    auth_http_method = "GET";
    token_endpoint = "https://auth.m7.rs/application/o/token/";
    token_params_mode = "RequestBodyForm";
    redirect_uri = "http://127.0.0.1:8765/callback";
    auth_scope = "openid profile email offline_access urn:ietf:params:oauth:scope:mail";
  };

  programs.aerc.extraBinds = lib.genAttrs ["messages:account=^lumis$" "view:account=^lumis$"] (_: {
    d = ":move \"Deleted Items\"<Enter>";
    D = ":move \"Deleted Items\"<Enter>";
  });

  accounts.email.accounts.lumis = {
    inherit address;
    realName = "Lumis";
    userName = address;
    passwordCommand = "${oama} access ${address}";
    imap.host = mailHost;
    smtp.host = mailHost;
    folders = {
      sent = "Sent Items";
      trash = "Deleted Items";
    };

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
      extraAccounts.folders-sort = ["Inbox" "Drafts" "Sent Items" "Junk Mail" "Deleted Items"];
    };
  };
}
