{
  config,
  pkgs,
  lib,
  outputs,
  ...
}: let
  derpPort = 3478;
  inherit (lib) listToAttrs flatten attrsToList mapAttrsToList attrByPath nameValuePair any;
  isSubstring = needle: haystack: (builtins.match ".*${needle}.*" haystack) != null;
  isRestrictedLocation = cfg: (isSubstring "allow fd7a:" cfg.extraConfig) || (isSubstring "allow 100." cfg.extraConfig);
  isRestricted = vhost: any ({value, ...}: isRestrictedLocation value) (attrsToList vhost.locations);
  domainToNode = listToAttrs (flatten (mapAttrsToList (
      name: host: let
        vhosts = attrByPath ["services" "nginx" "virtualHosts"] {} host.config;
      in
        flatten (mapAttrsToList (
            vhostName: vhostConfig: let
              aliases = vhostConfig.serverAliases or [];
            in
              lib.optional (isRestricted vhostConfig) (map (domain: nameValuePair domain name) ([vhostName] ++ aliases))
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
          nameservers.global = ["9.9.9.9"];
          extra_records_path = "/var/lib/headscale/extra-records.json";
        };
        server_url = "https://tailscale.m7.rs";
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
      "tailscale.m7.rs" = {
        forceSSL = true;
        enableACME = true;
        locations = {
          "/" = {
            proxyPass = "http://localhost:${toString config.services.headscale.port}";
            proxyWebsockets = true;
          };
          "/metrics" = {
            proxyPass = "http://${config.services.headscale.settings.metrics_listen_addr}/metrics";
          };
        };
      };
      "tailscale.misterio.me" = {
        forceSSL = true;
        enableACME = true;
        locations."/".return = "302 https://tailscale.m7.rs$request_uri";
      };
    };
  };

  systemd.services.headscale-extra-records = {
    description = "Generate headscale extra DNS records from live node list";
    after = ["headscale.service"];
    wants = ["headscale.service"];
    path = [pkgs.headscale pkgs.jq];
    script = ''
      JSON=$(headscale nodes list --output json 2>/dev/null || echo "[]")
      echo "$JSON" \
        | jq --argjson mapping '${builtins.toJSON domainToNode}' -r '
            reduce .[] as $node ({}; .[$node.given_name] = {
              v4: ([$node.ip_addresses[] | select(startswith("100."))] | first),
              v6: ([$node.ip_addresses[] | select(startswith("fd7a:"))] | first)
            }) as $ips
            | $mapping | to_entries
            | map(select($ips[.value].v4 != null)
              | [{ name: .key, type: "A",    value: $ips[.value].v4 },
                 { name: .key, type: "AAAA", value: $ips[.value].v6 }])
            | flatten
          ' > /var/lib/headscale/extra-records.json.new \
        && mv /var/lib/headscale/extra-records.json.new /var/lib/headscale/extra-records.json
    '';
    serviceConfig = {
      Type = "oneshot";
      # Stay active (exited) so a changed unit is re-run on nixos-rebuild switch;
      # an inactive oneshot is skipped by switch-to-configuration's restart pass.
      RemainAfterExit = true;
      User = "headscale";
      Group = "headscale";
    };
  };

  systemd.timers.headscale-extra-records = {
    description = "Hourly refresh of headscale extra DNS records";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };

  # Derp server
  networking.firewall.allowedUDPPorts = [derpPort];

  environment.systemPackages = [config.services.headscale.package];

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
