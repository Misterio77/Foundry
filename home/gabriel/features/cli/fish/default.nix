{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib) mkIf;
  packageNames = map (p: p.pname or p.name or null) config.home.packages;
  hasPackage = name: lib.any (x: x == name) packageNames;
  hasEza = hasPackage "eza";
  hasSpecialisationCli = hasPackage "specialisation";
  hasAwsCli = hasPackage "awscli2";
  hasNeomutt = config.programs.neomutt.enable;
in {
  imports = [
    ./tide.nix
    ./zoxide.nix
    ./bindings.nix
  ];
  home.packages = [pkgs.bash-completion];
  programs.fish = {
    enable = true;
    shellAbbrs = rec {
      jqless = "jq -C | less -r";

      watch = "viddy";

      s = mkIf hasSpecialisationCli "specialisation";

      ls = mkIf hasEza "eza";
      exa = ls;

      mutt = mkIf hasNeomutt "neomutt";
      m = mutt;

      aws-switch = mkIf hasAwsCli "export AWS_PROFILE=(aws configure list-profiles | fzf)";
      awssw = aws-switch;

      # ssh control-master helpers: open a bare background master (populates the
      # tmux picker), and fully close one. Abbrs so host-completion still works.
      mopen = "ssh -fN";
      mclose = "ssh -O exit";
    };
    shellAliases = {
      # Clear screen and scrollback
      clear = "printf '\\033[2J\\033[3J\\033[1;1H'";
    };
    functions = {
      # Disable greeting
      fish_greeting = "";
      # Merge history when pressing up
      up-or-search = lib.readFile ./up-or-search.fish;
      # Check stuff in PATH
      nix-inspect =
        /*
        fish
        */
        ''
          set -s PATH | grep "PATH\[.*/nix/store" | cut -d '|' -f2 |  grep -v -e "-man" -e "-terminfo" | perl -pe 's:^/nix/store/\w{32}-([^/]*)/bin$:\1:' | sort | uniq
        '';
      __fish_complete_bash =
        /*
        fish
        */
        ''
          set cmd (commandline -cp)
          bash -ic "source ${./get-bash-completions.sh}; get_completions '$cmd'"
        '';
      __fish_at_file_or_complete =
        /*
        fish
        */
        ''
          set -l token (commandline -ct)

          if not string match --quiet --regex '^@' -- $token
              commandline -f complete
              return
          end

          set -l query (string sub --start 2 -- $token)
          set -l selection

          if type --query fd
              set selection (fd --hidden --follow --exclude .git --exclude .jj --type file --type directory . 2>/dev/null | fzf --height 40% --reverse --query "$query" --select-1 --exit-0)
          else
              set selection (find . -path './.git' -prune -o -path './.jj' -prune -o -print 2>/dev/null | string replace --regex '^\\./' "" | fzf --height 40% --reverse --query "$query" --select-1 --exit-0)
          end

          if test -n "$selection"
              commandline -t (string escape -- $selection)
          end

          commandline -f repaint
        '';
    };
    interactiveShellInit =
      /*
      fish
      */
      ''
        # Open command buffer in editor when alt+e is pressed
        bind \ee edit_command_buffer

        # Use terminal colors
        set -gx fish_color_autosuggestion      brblack
        set -gx fish_color_cancel              -r
        set -gx fish_color_command             brgreen
        set -gx fish_color_comment             brmagenta
        set -gx fish_color_cwd                 green
        set -gx fish_color_cwd_root            red
        set -gx fish_color_end                 brmagenta
        set -gx fish_color_error               brred
        set -gx fish_color_escape              brcyan
        set -gx fish_color_history_current     --bold
        set -gx fish_color_host                normal
        set -gx fish_color_host_remote         yellow
        set -gx fish_color_match               --background=brblue
        set -gx fish_color_normal              normal
        set -gx fish_color_operator            cyan
        set -gx fish_color_param               brblue
        set -gx fish_color_quote               yellow
        set -gx fish_color_redirection         bryellow
        set -gx fish_color_search_match        'bryellow' '--background=brblack'
        set -gx fish_color_selection           'white' '--bold' '--background=brblack'
        set -gx fish_color_status              red
        set -gx fish_color_user                brgreen
        set -gx fish_color_valid_path          --underline
        set -gx fish_pager_color_completion    normal
        set -gx fish_pager_color_description   yellow
        set -gx fish_pager_color_prefix        'white' '--bold' '--underline'
        set -gx fish_pager_color_progress      'brwhite' '--background=cyan'
      '';
  };
}
