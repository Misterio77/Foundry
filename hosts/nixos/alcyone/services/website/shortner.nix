{lib, ...}: {
  services.nginx.virtualHosts."m7.rs" = {
    forceSSL = true;
    enableACME = true;
    locations = lib.mapAttrs' (n: v: lib.nameValuePair "/l/${n}" {return = "302 ${v}$request_uri";}) {
      "booletim" = "https://drive.google.com/uc?export=download&id=1cPemsZV3mUq9nfPMW1nKE7CssijMk7s0";
    };
  };
}
