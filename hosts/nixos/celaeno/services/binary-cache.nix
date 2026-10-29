{
  config,
  pkgs,
  ...
}: {
  sops.secrets.cache-sig-key = {
    sopsFile = ../secrets.yaml;
  };

  services = {
    nix-serve = {
      enable = true;
      secretKeyFile = config.sops.secrets.cache-sig-key.path;
      package = pkgs.nix-serve;
    };
    nginx.virtualHosts."cache.m7.rs" = {
      forceSSL = true;
      enableACME = true;
      # nix-serve hardcodes priority 30; prefer cache.nixos.org's priority 40.
      locations."= /nix-cache-info".extraConfig = ''
        default_type text/plain;
        return 200 "StoreDir: /nix/store\nWantMassQuery: 1\nPriority: 50\n";
      '';
      locations."/".extraConfig = ''
        proxy_pass http://localhost:${toString config.services.nix-serve.port};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      '';
    };
  };
}
