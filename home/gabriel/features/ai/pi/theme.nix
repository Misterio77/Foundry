{config, ...}: let
  name = "nix-colorscheme";
in {
  programs.pi-coding-agent.settings.theme = name;
  home.file.".pi/agent/themes/${name}.json".text = builtins.toJSON {
    "$schema" = "https://pi.dev/schemas/theme.schema.json";
    name = name;
    vars = config.colorscheme.colors;
    colors = {
      accent = "primary";
      border = "secondary";
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
      userMessageBg = "primary_container";
      userMessageText = "on_primary_container";
      customMessageBg = "secondary_container";
      customMessageText = "on_secondary_container";
      customMessageLabel = "primary";
      toolPendingBg = "surface_container";
      toolSuccessBg = "green_container";
      toolErrorBg = "error_container";
      toolTitle = "blue";
      toolOutput = "on_surface";

      mdHeading = "blue";
      mdLink = "red";
      mdLinkUrl = "orange";
      mdCode = "green";
      mdCodeBlock = "on_surface";
      mdCodeBlockBorder = "secondary";
      mdQuote = "cyan";
      mdQuoteBorder = "cyan";
      mdHr = "secondary";
      mdListBullet = "red";

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
