{
  services.nginx.virtualHosts."lumis.cards" = {
    forceSSL = true;
    enableACME = true;
    locations."/".return = "302 https://instagram.com/lumis.cards";
  };
}
