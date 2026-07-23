{
  config,
  pkgs,
  ...
}: {
  services.firefly-iii = {
    enable = true;
    package = pkgs.firefly-iii.overrideAttrs (old: rec {
      pname = "firefly-iii";
      version = "6.4.22";
      src = pkgs.fetchFromGitHub {
        owner = "firefly-iii";
        repo = "firefly-iii";
        tag = "v${version}";
        hash = "sha256-i20D0/z6GA7pZYrWvRJ8tUlptNI5Cl/e9UY0hKg9SP8=";
      };
      composerVendor = pkgs.php.mkComposerVendor {
        inherit pname src version;
        composerStrictValidation = true;
        strictDeps = true;
        vendorHash = "sha256-m+esW/yQs/GSwnw2iqVfSMXCf6/5M4634GUbt4Nnvbg=";
      };
      npmDeps = pkgs.fetchNpmDeps {
        inherit src;
        name = "${pname}-npm-deps";
        hash = "sha256-pu8dxL0NRB1cyqlQEf2zT2wdVp2fbe+Vp85qMs7f6s0=";
      };
    });
    settings = {
      APP_KEY_FILE = config.sops.secrets.firefly-key.path;
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

  services.nginx.virtualHosts.${config.services.firefly-iii.virtualHost} = {
    forceSSL = true;
    enableACME = true;
    locations."/".extraConfig = ''
      allow 127.0.0.1;
      allow ::1;
      allow ${config.services.headscale.settings.prefixes.v4};
      allow ${config.services.headscale.settings.prefixes.v6};
      deny all;
    '';
    locations."=/relatorio-layla" = {
      alias = "/srv/files/relatorio-financeiro.html";
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

  environment.persistence = {
    "/persist".directories = ["/var/lib/firefly-iii"];
  };
}
