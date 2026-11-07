{
  config,
  pkgs,
  lib,
  outputs,
  ...
}: let
  derpPort = 3478;
  controlDomain = "tailscale.m7.rs";
  inherit (lib) listToAttrs flatten attrsToList mapAttrsToList attrByPath nameValuePair any;
  isSubstring = needle: haystack: (builtins.match ".*${needle}.*" haystack) != null;
  hasTailnetAllowlist = cfg: (isSubstring "allow fd7a:" cfg.extraConfig) || (isSubstring "allow 100." cfg.extraConfig);
  isRestricted = vhost: (hasTailnetAllowlist vhost) || any ({value, ...}: hasTailnetAllowlist value) (attrsToList vhost.locations);
  domainToNode = listToAttrs (flatten (mapAttrsToList (
      name: host: let
        vhosts = attrByPath ["services" "nginx" "virtualHosts"] {} host.config;
      in
        flatten (mapAttrsToList (
            vhostName: vhostConfig: let
              aliases = vhostConfig.serverAliases or [];
            in
              # Coordination must remain reachable by tailscaled's tunnel-bypassing dialer.
              lib.optional (isRestricted vhostConfig) (map (domain: nameValuePair domain name) (lib.filter (domain: domain != controlDomain) ([vhostName] ++ aliases)))
          )
          vhosts)
    )
    outputs.nixosConfigurations));
in {
  services = {
    headscale = {
      enable = true;
      port = 8085;
      address = "127.0.0.1";
      settings = {
        dns = {
          override_local_dns = true;
          base_domain = "ts.m7.rs";
          magic_dns = true;
          nameservers.global = ["1.1.1.1" "1.0.0.1"];
          extra_records_path = "/var/lib/headscale/extra-records.json";
        };
        server_url = "https://${controlDomain}";
        metrics_listen_addr = "127.0.0.1:8095";
        logtail = {
          enabled = false;
        };
        log = {
          level = "warn";
        };
        prefixes = {
          v4 = "100.77.0.0/24";
          v6 = "fd7a:115c:a1e0:77::/64";
        };
        derp.server = {
          enable = true;
          region_id = 999;
          stun_listen_addr = "0.0.0.0:${toString derpPort}";
        };
      };
    };

    nginx.virtualHosts = {
      ${controlDomain} = {
        forceSSL = true;
        enableACME = true;
        locations = {
          "/" = {
            proxyPass = "http://${config.services.headscale.address}:${toString config.services.headscale.port}";
            proxyWebsockets = true;
          };
          "/metrics" = {
            proxyPass = "http://${config.services.headscale.settings.metrics_listen_addr}/metrics";
            extraConfig = ''
              if ($ssl_client_verify != SUCCESS) {
                return 403;
              }
            '';
          };
        };
      };
      "tailscale.misterio.me" = {
        forceSSL = true;
        enableACME = true;
        locations."/".return = "302 https://${controlDomain}$request_uri";
      };
    };
  };

  # Headscale reads this before opening the API used by the generator.
  systemd.services.headscale.preStart = ''
    if [ ! -e /var/lib/headscale/extra-records.json ]; then
      printf '[]\n' > /var/lib/headscale/extra-records.json
    fi
  '';

  systemd.services.headscale-extra-records = {
    description = "Generate headscale extra DNS records from live node list";
    after = ["headscale.service"];
    wants = ["headscale.service"];
    startLimitIntervalSec = 0;
    path = [config.services.headscale.package pkgs.jq];
    script = ''
      set -euo pipefail
      records=/var/lib/headscale/extra-records.json
      tmp=$(mktemp "$records.XXXXXX")
      trap 'rm -f "$tmp"' EXIT

      JSON=$(headscale nodes list --output json)
      printf '%s\n' "$JSON" \
        | jq -e --argjson mapping '${builtins.toJSON domainToNode}' '
            if type != "array" then error("expected a node array") else . end
            | reduce .[] as $node ({}; .[$node.given_name] = {
              v4: ([$node.ip_addresses[] | select(startswith("100."))] | first),
              v6: ([$node.ip_addresses[] | select(startswith("fd7a:"))] | first)
            }) as $ips
            | $mapping | to_entries
            | map(
                if $ips[.value].v4 == null or $ips[.value].v6 == null
                then error("missing tailnet addresses for \(.value)")
                else [{ name: .key, type: "A",    value: $ips[.value].v4 },
                      { name: .key, type: "AAAA", value: $ips[.value].v6 }]
                end)
            | flatten
          ' > "$tmp"
      if ! cmp -s "$tmp" "$records"; then
        mv "$tmp" "$records"
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "headscale";
      Group = "headscale";
      # Type=simple ordering is not API readiness; retry failed snapshots instead.
      Restart = "on-failure";
      RestartSec = "15s";
      TimeoutStartSec = "30s";
    };
  };

  systemd.timers.headscale-extra-records = {
    description = "Refresh headscale extra DNS records hourly and on generator changes";
    wantedBy = ["timers.target"];
    # Restarting the timer re-arms OnActiveSec when the generator changes on switch.
    restartTriggers = [config.systemd.services.headscale-extra-records.serviceConfig.ExecStart];
    timerConfig = {
      OnActiveSec = "1s";
      OnCalendar = "hourly";
      AccuracySec = "1s";
      Persistent = true;
    };
  };

  # Derp server
  networking.firewall.allowedUDPPorts = [derpPort];

  environment.systemPackages = [config.services.headscale.package];

  services.borgbackup.jobs.alcyone.paths = ["/var/lib/headscale"];

  environment.persistence = {
    "/persist".directories = [
      {
        directory = "/var/lib/headscale";
        user = config.services.headscale.user;
        group = config.services.headscale.group;
        mode = "0700";
      }
    ];
  };
}
