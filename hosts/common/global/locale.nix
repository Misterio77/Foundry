{lib, ...}: {
  i18n = {
    defaultLocale = lib.mkDefault "en_US.UTF-8";
    extraLocaleSettings = {
      LC_TIME = lib.mkDefault "pt_BR.UTF-8";
      LC_MEASUREMENT = lib.mkDefault "pt_BR.UTF-8";
      LC_MONETARY = lib.mkDefault "pt_BR.UTF-8";
    };
    extraLocales = lib.mkDefault [
      "en_US.UTF-8/UTF-8"
      "pt_BR.UTF-8/UTF-8"
    ];
  };
  time.timeZone = lib.mkDefault "America/Sao_Paulo";
  location.provider = "geoclue2";
}
