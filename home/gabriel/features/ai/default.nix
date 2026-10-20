{pkgs, ...}: {
  imports = [
    ./hax
    ./pi
  ];

  home.packages = [
    pkgs.python3
    pkgs.python3Packages.trafilatura
  ];
}
