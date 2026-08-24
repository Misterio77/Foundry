{pkgs, ...}: {
  # Install skill
  programs.pi-coding-agent.settings.packages = [pkgs.agent-browser];
  # Make CLI available globally on the user
  home.packages = [pkgs.agent-browser];
}
