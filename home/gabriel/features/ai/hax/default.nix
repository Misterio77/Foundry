{
  programs.hax = {
    enable = true;
    context = ../common/context.md;
    skills = ../common/skills;
    settings.system_prompt = "@system-prompt.md";
  };

  # Base prompt vendored from hax v0.5.0, src/agent_core.c (MIT).
  # Environment, AGENTS.md, skills, and delegation guidance are still appended by hax.
  xdg.configFile."hax/system-prompt.md".source = ./system-prompt.md;
}
