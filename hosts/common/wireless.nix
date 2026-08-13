{config, ...}: {
  sops.secrets.wireless = {
    sopsFile = ./secrets.yaml;
    owner = config.users.users.wpa_supplicant.name;
    group = config.users.users.wpa_supplicant.group;
  };

  networking.wireless = {
    enable = true;
    fallbackToWPA2 = false;
    # The sandbox binds secretsFile into the unit's namespace, so a secret that
    # can't be decrypted kills the daemon (and the control socket needed to
    # connect by hand and fix it). Also breaks wpa_gui.
    enableHardening = false;
    # Declarative
    secretsFile = config.sops.secrets.wireless.path;
    networks = {
      "CAT_HOUSE" = {
        pskRaw = "ext:cat_house";
      };
      "Marcos_2.4Ghz" = {
        pskRaw = "ext:marcos_24";
      };
      "Marcos_5Ghz" = {
        pskRaw = "ext:marcos_50";
      };
      "Misterio" = {
        pskRaw = "ext:misterio";
        authProtocols = ["WPA-PSK"];
        # extraConfig = ''
        #   mesh_fwding=1
        # '';
      };
      "VIVOFIBRA-FC41-5G" = {
        pskRaw = "ext:marcos_santos_5g";
      };
      "Nijland" = {
        pskRaw = "ext:nijland";
      };
      "eduroam" = {
        authProtocols = ["WPA-EAP"];
        auth = ''
          pairwise=CCMP
          group=CCMP TKIP
          eap=TTLS
          domain_suffix_match="semfio.usp.br"
          ca_cert="${./eduroam-cert.pem}"
          identity="10856803@usp.br"
          password=ext:eduroam
          phase2="auth=MSCHAPV2"
        '';
      };
    };

    # Imperative
    allowAuxiliaryImperativeNetworks = true;
    userControlled = true;
  };
}
