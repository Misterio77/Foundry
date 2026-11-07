{
  config,
  pkgs,
  ...
}: {
  sops.secrets = {
    grafana-mail-password = {
      sopsFile = ../../secrets.yaml;
      owner = "grafana";
    };
    grafana-key = {
      sopsFile = ../../secrets.yaml;
      owner = "grafana";
    };
  };

  services = {
    grafana = {
      enable = true;
      declarativePlugins = [pkgs.grafanaPlugins.prometheus];
      settings = {
        plugins.plugin_admin_enabled = false;
        security.secret_key = "$__file{${config.sops.secrets.grafana-key.path}}";
        server.http_port = 3000;
        users.default_theme = "system";
        dashboards.default_home_dashboard_path = "${./dashboards}/hosts.json";
        feature_toggles.enable = "dashboardSectionVariables";
        security = {
          disable_initial_admin_creation = true;
          cookie_secure = true;
        };
        auth = {
          disable_login = true;
          disable_login_form = true;
          oauth_allow_insecure_email_lookup = false;
          signout_redirect_url = "https://auth.m7.rs/application/o/grafana/end-session/";
        };
        "auth.basic".enabled = false;
        "auth.generic_oauth" = {
          enabled = true;
          auto_login = true;
          name = "Authentik";
          allow_sign_up = true;
          client_id = "grafana";
          client_secret = "$__file{${config.sops.secrets.authentik-grafana-client-secret.path}}";
          scopes = "openid profile email grafana_roles";
          auth_url = "https://auth.m7.rs/application/o/authorize/";
          token_url = "https://auth.m7.rs/application/o/token/";
          api_url = "https://auth.m7.rs/application/o/userinfo/";
          use_pkce = true;
          use_refresh_token = false;
          backchannel_logout = true;
          oidc_issuer = "https://auth.m7.rs/application/o/grafana/";
          jwk_set_url = "https://auth.m7.rs/application/o/grafana/jwks/";
          validate_id_token = true;
          login_attribute_path = "preferred_username";
          role_attribute_path = "grafana_role";
          role_attribute_strict = true;
          allow_assign_grafana_admin = false;
        };
        "auth.anonymous" = {
          enabled = false;
        };
        smtp = rec {
          enabled = true;
          host = "mail.m7.rs:465";
          from_address = user;
          user = config.mailserver.accounts."grafana@m7.rs".name;
          password = "$__file{${config.sops.secrets.grafana-mail-password.path}}";
        };
        server.root_url = "https://dash.m7.rs/";
      };
      provision = {
        enable = true;
        dashboards.settings.providers = [
          {
            options.path = ./dashboards;
          }
        ];
        datasources.settings = {
          apiVersion = 1;
          datasources = [
            {
              name = "Prometheus";
              type = "prometheus";
              access = "proxy";
              url = "https://metrics.m7.rs";
              uid = "prometheus-default";
              isDefault = true;
            }
          ];
        };
        alerting = {
          contactPoints.settings = {
            apiVersion = 1;
            contactPoints = [
              {
                name = "default";
                receivers = [
                  {
                    uid = "alerts-email";
                    type = "email";
                    settings.addresses = "<alerts@m7.rs>";
                  }
                ];
              }
            ];
          };
          policies.settings = {
            apiVersion = 1;
            policies = [
              {
                receiver = "default";
                group_wait = "30s"; # Time to wait for others in group before sending (for batching)
                group_interval = "1m"; # Time to wait before sending update about changes in the same group
                repeat_interval = "4h"; # Time to wait before re-emiting notifications already sent
              }
            ];
          };
          rules.settings = {
            apiVersion = 1;
            groups = [
              {
                name = "default";
                folder = "alerts";
                interval = "30s"; # Interval to check rules
                orgId = 1;
                rules = [
                  {
                    title = "Low disk";
                    uid = "low-disk-alert";
                    notification_settings.receiver = "default";
                    annotations = {
                      summary = "{{ $labels.instance }} is low on storage";
                      description = "{{ $labels.label }} at {{ $labels.instance }} is below 10% capacity.";
                    };
                    condition = "B";
                    execErrState = "KeepLast";
                    noDataState = "KeepLast";
                    data = [
                      {
                        refId = "A";
                        datasourceUid = "prometheus-default";
                        model = {
                          refId = "A";
                          intervalMs = 1000;
                          expr = "sum by (job, instance, uuid) (node_btrfs_used_bytes) / sum by (job, instance, uuid) (node_btrfs_device_size_bytes) * on(uuid) group_left(label) node_btrfs_info";
                          instant = true;
                          range = false;
                          legendFormat = "__auto";
                          maxDataPoints = 43200;
                        };
                        relativeTimeRange = {
                          from = 600;
                          to = 0;
                        };
                      }
                      {
                        refId = "B";
                        datasourceUid = "__expr__";
                        model = {
                          refId = "B";
                          intervalMs = 1000;
                          maxDataPoints = 43200;
                          type = "threshold";
                          expression = "A";
                          datasource = {
                            type = "__expr__";
                            uid = "__expr__";
                          };
                          conditions = [
                            {
                              type = "query";
                              query.params = ["B"];
                              evaluator = {
                                type = "gt";
                                params = [0.9];
                              };
                              operator.type = "and";
                              reducer.type = "last";
                            }
                          ];
                        };
                      }
                    ];
                  }
                  {
                    title = "Read-only Btrfs filesystem";
                    uid = "btrfs-read-only";
                    notification_settings.receiver = "default";
                    annotations = {
                      summary = "{{ $labels.instance }} has a read-only Btrfs filesystem";
                      description = "{{ $labels.device }} mounted at {{ $labels.mountpoint }} on {{ $labels.instance }} has been read-only for at least one minute.";
                    };
                    condition = "B";
                    execErrState = "KeepLast";
                    noDataState = "KeepLast";
                    for = "1m";
                    data = [
                      {
                        refId = "A";
                        datasourceUid = "prometheus-default";
                        model = {
                          refId = "A";
                          intervalMs = 1000;
                          expr = ''max by (job, instance, device, mountpoint) (node_filesystem_readonly{job="hosts",fstype="btrfs",mountpoint!="/nix/store"})'';
                          instant = true;
                          range = false;
                          legendFormat = "__auto";
                          maxDataPoints = 43200;
                        };
                        relativeTimeRange = {
                          from = 600;
                          to = 0;
                        };
                      }
                      {
                        refId = "B";
                        datasourceUid = "__expr__";
                        model = {
                          refId = "B";
                          intervalMs = 1000;
                          maxDataPoints = 43200;
                          type = "threshold";
                          expression = "A";
                          datasource = {
                            type = "__expr__";
                            uid = "__expr__";
                          };
                          conditions = [
                            {
                              type = "query";
                              query.params = ["B"];
                              evaluator = {
                                type = "gt";
                                params = [0];
                              };
                              operator.type = "and";
                              reducer.type = "last";
                            }
                          ];
                        };
                      }
                    ];
                  }
                  {
                    title = "Service down";
                    uid = "service-down";
                    notification_settings.receiver = "default";
                    annotations = {
                      summary = "{{ $labels.instance }} down";
                      description = "{{ $labels.instance }} ({{ $labels.job }}) is not reachable.";
                    };
                    condition = "B";
                    execErrState = "KeepLast";
                    noDataState = "KeepLast";
                    for = "3m"; # Higher than 'interval' (30s), to avoid blips generating notifications
                    data = [
                      {
                        refId = "A";
                        datasourceUid = "prometheus-default";
                        model = {
                          refId = "A";
                          intervalMs = 1000;
                          expr = "up{job!=\"hosts\"}"; # Hosts can be down sometimes, but not services
                          instant = true;
                          range = false;
                          legendFormat = "__auto";
                          maxDataPoints = 43200;
                        };
                        relativeTimeRange = {
                          from = 600;
                          to = 0;
                        };
                      }
                      {
                        refId = "B";
                        datasourceUid = "__expr__";
                        model = {
                          refId = "B";
                          intervalMs = 1000;
                          maxDataPoints = 43200;
                          type = "threshold";
                          expression = "A";
                          datasource = {
                            type = "__expr__";
                            uid = "__expr__";
                          };
                          conditions = [
                            {
                              type = "query";
                              query.params = ["B"];
                              evaluator = {
                                type = "ne";
                                params = [1];
                              };
                              operator.type = "and";
                              reducer.type = "last";
                            }
                          ];
                        };
                      }
                    ];
                  }
                ];
              }
            ];
          };
        };
      };
    };
    nginx.virtualHosts = {
      "dash.m7.rs" = let
        port = config.services.grafana.settings.server.http_port;
      in {
        forceSSL = true;
        enableACME = true;
        locations."= /metrics" = {
          proxyPass = "http://localhost:${toString port}";
          extraConfig = ''
            if ($ssl_client_verify != SUCCESS) {
              return 403;
            }
          '';
        };
        locations."/" = {
          proxyPass = "http://localhost:${toString port}";
        };
      };
    };
  };
}
