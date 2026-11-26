{
  services.nginx.virtualHosts."lumis.cards" = {
    forceSSL = true;
    enableACME = true;
    root = ../../../../projects/lumis;
  };
}
