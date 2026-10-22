{pkgs, ...}: {
  imports = [
    ./fish
    ./nushell

    ./bash.nix
    ./bat.nix
    ./codex-imagegen.nix
    ./direnv.nix
    ./gh.nix
    ./git.nix
    ./gpg.nix
    ./jujutsu.nix
    ./less.nix
    ./nix-index.nix
    ./pfetch.nix
    ./ssh.nix
    ./tmux.nix
    ./web-search.nix
    ./xpo.nix
    ./fzf.nix
    ./mandoc.nix
  ];
  home.packages = with pkgs; [
    comma # Install and run programs by sticking a , before them
    distrobox # Nice escape hatch, integrates docker images with my environment

    bc # Calculator
    bottom # System viewer
    ncdu # TUI disk usage
    eza # Better ls
    ripgrep # Better grep
    fd # Better find
    httpie # Better curl
    jq # JSON pretty printer and manipulator
    timer # To help with my ADHD paralysis
    viddy # Better watch
    unzip # Always useful
    overleaf-sync # Synchronize LaTeX projects with Overleaf

    nixd # Nix LSP
    alejandra # Nix formatter
    nixfmt
    nvd # Differ
    nix-diff # Differ, more detailed
    nix-output-monitor
    nh # Nice wrapper for NixOS and HM
  ];
}
