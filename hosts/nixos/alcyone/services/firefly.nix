{
  config,
  lib,
  pkgs,
  ...
}: let
  browserAuth = ''
    auth_request /_firefly_auth;
    auth_request_set $firefly_principal $upstream_http_x_foundry_firefly_principal;
    auth_request_set $firefly_email $upstream_http_x_foundry_firefly_email;
    auth_request_set $firefly_cookie $upstream_http_set_cookie;
    add_header Set-Cookie $firefly_cookie always;
    error_page 401 = @firefly_login;
  '';
  fastcgi = ''
    include ${config.services.nginx.package}/conf/fastcgi_params;
    fastcgi_param SCRIPT_FILENAME ${config.services.firefly-iii.package}/public/index.php;
    fastcgi_param SCRIPT_NAME /index.php;
    fastcgi_param modHeadersAvailable true;
    fastcgi_pass unix:${config.services.phpfpm.pools.firefly-iii.socket};
  '';
  browserFastcgi =
    browserAuth
    + fastcgi
    + ''
      # CGI variables cannot be supplied by client HTTP headers.
      fastcgi_param REMOTE_USER $firefly_principal;
      fastcgi_param REMOTE_EMAIL $firefly_email;
    '';
in {
  services.firefly-iii = {
    enable = true;
    package = pkgs.firefly-iii.overrideAttrs (old: {
      postInstall =
        old.postInstall
        + ''
          ln -s ${config.services.firefly-iii.dataDir}/storage $out/storage
          ln -s ${config.services.firefly-iii.dataDir}/cache $out/bootstrap/cache
        '';
    });
    settings = {
      APP_KEY_FILE = config.sops.secrets.firefly-key.path;
      AUTHENTICATION_GUARD = "remote_user_guard";
      AUTHENTICATION_GUARD_HEADER = "REMOTE_USER";
      AUTHENTICATION_GUARD_EMAIL = "REMOTE_EMAIL";
      CUSTOM_LOGOUT_URL = "https://firefly.m7.rs/outpost.goauthentik.io/sign_out";
      ENABLE_EXCHANGE_RATES = "true";
      ENABLE_EXTERNAL_RATES = "false";
      SITE_OWNER = "hi@m7.rs";
      MAIL_MAILER = "smtp";
      MAIL_FROM = "firefly@m7.rs";
      MAIL_HOST = "mail.m7.rs";
      MAIL_PORT = 465;
      MAIL_ENCRYPTION = "tls";
      MAIL_USERNAME = "firefly@m7.rs";
      MAIL_PASSWORD = config.sops.secrets.firefly-mail-password.path;
    };
    enableNginx = true;
    virtualHost = "firefly.m7.rs";
  };
  systemd.services = {
    firefly-iii-cron.environment.TZ = config.time.timeZone;
    firefly-iii-setup.environment.TZ = config.time.timeZone;
    phpfpm-firefly-iii.environment.TZ = config.time.timeZone;
  };

  services.nginx.virtualHosts.${config.services.firefly-iii.virtualHost} = {
    forceSSL = true;
    enableACME = true;
    extraConfig = ''
      allow 127.0.0.1;
      allow ::1;
      allow ${config.services.headscale.settings.prefixes.v4};
      allow ${config.services.headscale.settings.prefixes.v6};
      deny all;
    '';
    locations = lib.mkForce {
      "/" = {
        tryFiles = "$uri @firefly";
        extraConfig = browserAuth;
      };
      "@firefly".extraConfig = browserFastcgi;
      "= /index.php".extraConfig = browserFastcgi;
      "~ \\.php(?:/|$)".return = "404";
      "^~ /api/".extraConfig =
        fastcgi
        + ''
          # Passport validates PATs (or its own CSRF-protected browser API cookie).
          fastcgi_param REMOTE_USER "";
          fastcgi_param REMOTE_EMAIL "";
        '';
      "= /_firefly_auth" = {
        proxyPass = "http://127.0.0.1:9000/outpost.goauthentik.io/auth/nginx";
        recommendedProxySettings = false;
        extraConfig = ''
          internal;
          proxy_pass_request_body off;
          proxy_set_header Content-Length "";
          proxy_set_header Host firefly.m7.rs;
          # Do not let reserved outpost paths bypass authentication.
          proxy_set_header X-Original-URL https://firefly.m7.rs/;
          proxy_set_header X-Forwarded-Host firefly.m7.rs;
          proxy_set_header X-Forwarded-Proto https;
          proxy_set_header X-Forwarded-For $remote_addr;
          proxy_set_header Authorization "";
        '';
      };
      "^~ /outpost.goauthentik.io/" = {
        proxyPass = "http://127.0.0.1:9000";
        recommendedProxySettings = false;
        extraConfig = ''
          proxy_set_header Host firefly.m7.rs;
          proxy_set_header X-Original-URL https://firefly.m7.rs/;
          proxy_set_header X-Forwarded-Host firefly.m7.rs;
          proxy_set_header X-Forwarded-Proto https;
          proxy_set_header X-Forwarded-For $remote_addr;
          proxy_set_header Authorization "";
        '';
      };
      "@firefly_login".extraConfig = ''
        add_header Set-Cookie $firefly_cookie always;
        return 302 /outpost.goauthentik.io/start?rd=https://firefly.m7.rs/;
      '';
    };
  };

  systemd.services.firefly-sync-ptax = {
    description = "Sync card-adjusted PTAX rates to Firefly III";
    after = ["network-online.target" "nginx.service" "phpfpm-firefly-iii.service" "firefly-iii-setup.service"];
    wants = ["network-online.target"];
    startAt = "daily";
    path = [pkgs.coreutils pkgs.curl pkgs.jq];
    script = ''
      set -uo pipefail

      end_date=$(date +%m-%d-%Y)
      start_date=$(date --date='10 days ago' +%m-%d-%Y)
      ptax_base='https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata'

      usd_quote=$(
        curl --fail-with-body --silent --show-error --get \
          "$ptax_base/CotacaoDolarPeriodo(dataInicial=@dataInicial,dataFinalCotacao=@dataFinalCotacao)" \
          --data-urlencode "@dataInicial='$start_date'" \
          --data-urlencode "@dataFinalCotacao='$end_date'" \
          --data-urlencode '$format=json' \
        | jq -er '.value | max_by(.dataHoraCotacao) | [.dataHoraCotacao[0:10], .cotacaoVenda] | @tsv'
      )

      eur_quote=$(
        curl --fail-with-body --silent --show-error --get \
          "$ptax_base/CotacaoMoedaPeriodo(moeda=@moeda,dataInicial=@dataInicial,dataFinalCotacao=@dataFinalCotacao)" \
          --data-urlencode "@moeda='EUR'" \
          --data-urlencode "@dataInicial='$start_date'" \
          --data-urlencode "@dataFinalCotacao='$end_date'" \
          --data-urlencode '$format=json' \
        | jq -er '.value | map(select(.tipoBoletim == "Fechamento")) | max_by(.dataHoraCotacao) | [.dataHoraCotacao[0:10], .cotacaoVenda] | @tsv'
      )

      token=$(<"$CREDENTIALS_DIRECTORY/firefly-pat")
      for entry in "USD"$'\t'"$usd_quote" "EUR"$'\t'"$eur_quote"; do
        IFS=$'\t' read -r currency quote_date ptax <<<"$entry"
        rate=$(jq -nr --arg rate "$ptax" '$rate | tonumber * 1.035')
        payload=$(jq -n \
          --arg date "$quote_date" \
          --arg from "$currency" \
          --arg rate "$rate" \
          '{date: $date, from: $from, to: "BRL", rate: $rate}')

        curl --fail-with-body --silent --show-error \
          --resolve firefly.m7.rs:443:127.0.0.1 \
          --request POST \
          --header "Authorization: Bearer $token" \
          --header 'Accept: application/vnd.api+json' \
          --header 'Content-Type: application/json' \
          --data "$payload" \
          https://firefly.m7.rs/api/v1/exchange-rates >/dev/null

        echo "$quote_date: set $currency/BRL to $rate (PTAX $ptax + 3.5%)"
      done
    '';
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      LoadCredential = "firefly-pat:${config.sops.secrets.firefly-pat.path}";
    };
  };

  sops.secrets = {
    firefly-pat.sopsFile = ../secrets.yaml;
    firefly-key = {
      owner = "firefly-iii";
      group = "nginx";
      sopsFile = ../secrets.yaml;
    };
    firefly-mail-password = {
      owner = "firefly-iii";
      group = "nginx";
      sopsFile = ../secrets.yaml;
    };
  };

  services.borgbackup.jobs.alcyone.paths = ["/var/lib/firefly-iii"];

  environment.persistence = {
    "/persist".directories = ["/var/lib/firefly-iii"];
  };
}
