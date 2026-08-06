{pkgs, lib, ...}: let
  firefox = pkgs.wrapFirefox pkgs.firefox-unwrapped {
    extraPolicies = {
      AutofillAddressEnabled = false;
      AutofillCreditCardEnabled = false;
      CaptivePortal = false;
      DisableFeedbackCommands = true;
      DisableFirefoxAccounts = true;
      DisableFirefoxScreenshots = true;
      DisableFirefoxStudies = true;
      DisablePocket = true;
      DisableSetDesktopBackground = true;
      DisableTelemetry = true;
      DisplayBookmarksToolbar = "never";
      DisplayMenuBar = "never";
      DontCheckDefaultBrowser = true;
      NewTabPage = false;
      NoDefaultBookmarks = true;
      OfferToSaveLogins = false;
      OfferToSaveLoginsDefault = false;
      OverrideFirstRunPage = "";
      OverridePostUpdatePage =  "";
      PasswordManagerEnabled = false;
      FirefoxHome = {
        Search = true;
        Pocket = false;
        Snippets = false;
        TopSites = false;
        Highlights = false;
      };
      Homepage.URL = "about:blank";
      UserMessaging = {
        ExtensionRecommendations = false;
        SkipOnboarding = true;
      };
    };
  };
  firefox-kiosk = pkgs.writeShellScriptBin "firefox-kiosk" ''
    systemctl --user import-environment DISPLAY WAYLAND_DISPLAY
    systemctl --user start firefox-kiosk-session.target
    ${lib.getExe' pkgs.pulseaudio "pactl"} set-sink-volume @DEFAULT_SINK@ 80%
    ${lib.getExe pkgs.cage} -- ${lib.getExe firefox}
    systemctl --user stop firefox-kiosk-session.target
  '';

  firefox-kiosk-session =
    (pkgs.writeTextDir "share/wayland-sessions/firefox.desktop" ''
      [Desktop Entry]
      Name=Firefox Kiosk
      Comment=A web browser
      Exec=${lib.getExe firefox-kiosk}
      Type=Application
    '').overrideAttrs
      (_: {
        passthru.providedSessions = ["firefox"];
      });
in {
  services.displayManager.sessionPackages = [firefox-kiosk-session];

  systemd.user.targets.firefox-kiosk-session = {
    description = "Firefox session";
    bindsTo = ["graphical-session.target"];
    wants = ["graphical-session-pre.target"];
    after = ["graphical-session-pre.target"];
  };
}
