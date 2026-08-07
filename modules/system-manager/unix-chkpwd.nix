# nixpkgs' pam_unix execs its verification helper from the fixed path
# /run/wrappers/bin/unix_chkpwd, so pam_unix auth silently fails until that
# setuid wrapper exists. system-manager doesn't provide it (NixOS does), so set
# it up unconditionally for any nix PAM caller — root (e.g. greetd) and
# unprivileged (e.g. hyprlock) alike.
{pkgs, ...}: {
  security.wrappers.unix_chkpwd = {
    setuid = true;
    owner = "root";
    group = "root";
    source = "${pkgs.linux-pam}/bin/unix_chkpwd";
  };
}
