{ writeShellApplication, ruby, bundix }: writeShellApplication {
  name = "bundle-lock";
  runtimeInputs = [ ruby bundix ];
  text = ''
    bundle lock
    bundix --gemset nix/packages/gemset.nix
  '';
}
