{config, ...}: let
  name = "nix-colorscheme";
in {
  programs.pi-coding-agent.settings.theme = name;
  home.file.".pi/agent/themes/${name}.json".text = builtins.toJSON {
    "$schema" = "https://raw.githubusercontent.com/badlogic/pi-mono/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json";
    name = name;
    vars = config.colorscheme.colors;
    colors = {
      accent = "primary";
      border = "outline_variant";
      borderAccent = "primary";
      borderMuted = "surface_variant";
      success = "green";
      error = "error";
      warning = "yellow";
      muted = "on_surface_variant";
      dim = "outline";
      text = "on_surface";
      thinkingText = "on_surface_variant";

      selectedBg = "primary_container";
      userMessageBg = "surface_container_high";
      userMessageText = "on_surface";
      customMessageBg = "secondary_container";
      customMessageText = "on_secondary_container";
      customMessageLabel = "primary";
      toolPendingBg = "surface_container";
      toolSuccessBg = "green_container";
      toolErrorBg = "error_container";
      toolTitle = "primary";
      toolOutput = "on_surface";

      mdHeading = "primary";
      mdLink = "blue";
      mdLinkUrl = "on_surface_variant";
      mdCode = "cyan";
      mdCodeBlock = "on_surface";
      mdCodeBlockBorder = "surface_variant";
      mdQuote = "on_surface_variant";
      mdQuoteBorder = "outline_variant";
      mdHr = "outline_variant";
      mdListBullet = "cyan";

      toolDiffAdded = "green";
      toolDiffRemoved = "red";
      toolDiffContext = "on_surface_variant";

      syntaxComment = "on_surface_variant";
      syntaxKeyword = "magenta";
      syntaxFunction = "blue";
      syntaxVariable = "red";
      syntaxString = "green";
      syntaxNumber = "orange";
      syntaxType = "yellow";
      syntaxOperator = "on_surface";
      syntaxPunctuation = "outline";

      thinkingOff = "outline_variant";
      thinkingMinimal = "secondary";
      thinkingLow = "blue";
      thinkingMedium = "cyan";
      thinkingHigh = "magenta";
      thinkingXhigh = "red";

      bashMode = "orange";
    };
    export = {
      pageBg = "surface";
      cardBg = "surface_container";
      infoBg = "secondary_container";
    };
  };
}
