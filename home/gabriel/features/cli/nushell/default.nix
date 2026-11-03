{
  imports = [
    ./jc.nix
  ];
  programs.nushell = {
    enable = true;
    extraConfig = /* nu */ ''
      def create_title [] {
        let prefix = if SSH_TTY in $env {$"[(hostname | str replace -r "\\..*" "")] "}
        let path = pwd | str replace $env.HOME "~"
        ([$prefix, $path] | str join)
      }

      $env.config = {
        edit_mode: vi,
        show_banner: false,
        use_kitty_protocol: true,
        shell_integration: {
          osc2: false,
          osc7: true,
          osc8: true,
          osc133: true,
          osc633: true,
          reset_application_mode: true,
        },
        completions: {
          algorithm: "fuzzy",
        },
        history: {
          sync_on_enter: true,
        },
        hooks: {
          pre_prompt: [{
            print -n $"(ansi title)(create_title)(ansi st)"
          }]
        }
      }

      source ${./prompt.nu}
      source ${./completion.nu}
    '';
    loadSessionVariables = true;
  };
}
