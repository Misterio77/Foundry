{pkgs, ...}: let
  # greetd/swaylock link nix's linux-pam, which only understands
  # `include`/`substack` (not Ubuntu's Debian `@include`) and can only load
  # nix's own modules by absolute path. So we can't chain into Ubuntu's
  # /etc/pam.d/login stack; use self-contained stacks built from nix modules.
  pamSecurity = "${pkgs.linux-pam}/lib/security";
  pamAuth = ''
    auth      [success=1 default=ignore] ${pamSecurity}/pam_unix.so nullok
    auth      requisite                  ${pamSecurity}/pam_deny.so
    auth      required                   ${pamSecurity}/pam_permit.so
  '';
in {
  environment.etc = {
    # A prior activation can leave these files on disk but untracked.
    # replaceExisting backs them up instead of aborting on reactivation.
    "pam.d/greetd" = {
      replaceExisting = true;
      # greetd authenticates as root, so pam_unix reads /etc/shadow directly.
      # pam_systemd registers the logind session the Wayland session relies on
      # (XDG_RUNTIME_DIR, seat).
      text =
        pamAuth
        + ''

          account   [success=1 default=ignore] ${pamSecurity}/pam_unix.so
          account   requisite                  ${pamSecurity}/pam_deny.so
          account   required                   ${pamSecurity}/pam_permit.so

          password  required                   ${pamSecurity}/pam_deny.so

          session   required                   ${pamSecurity}/pam_loginuid.so
          session   required                   ${pamSecurity}/pam_unix.so
          session   optional                   ${pamSecurity}/pam_env.so
          session   optional                   ${pkgs.systemd}/lib/security/pam_systemd.so
        '';
    };
    "pam.d/swaylock" = {
      replaceExisting = true;
      # swaylock only authenticates (to unlock) and runs unprivileged, so
      # pam_unix reaches /etc/shadow via the setuid unix_chkpwd wrapper.
      text = pamAuth;
    };
  };
}
