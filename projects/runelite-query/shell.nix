{pkgs ? import <nixpkgs> {}}:
pkgs.mkShell {
  packages = [pkgs.jdk11];
}
