{
  hostname = import ./hostname.nix;
  systemd-default-path = import ./systemd-default-path.nix;
  unix-chkpwd = import ./unix-chkpwd.nix;
  wireless = import ./wireless.nix;
}
