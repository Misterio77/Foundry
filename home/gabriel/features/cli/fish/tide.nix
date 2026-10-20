{pkgs, ...}: {
  programs.fish = {
    plugins = [
      {
        name = "tide";
        src = pkgs.fetchFromGitHub {
          owner = "IlanCosman";
          repo = "tide";
          tag = "v6.2.0";
          hash = "sha256-1ApDjBUZ1o5UyfQijv9a3uQJ/ZuQFfpNmHiDWzoHyuw=";
        };
      }
    ];
    interactiveShellInit = /* fish */ ''
      set -x tide_character_color "brgreen"
      set -x tide_character_color_failure "brred"
      set -x tide_character_icon ">"
      set -x tide_character_vi_icon_default "<"
      set -x tide_character_vi_icon_replace "|"
      set -x tide_character_vi_icon_visual "V"

      set -x tide_status_bg_color "normal"
      set -x tide_status_bg_color_failure "normal"
      set -x tide_status_color "green"
      set -x tide_status_color_failure "red"
      set -x tide_status_icon "✔"
      set -x tide_status_icon_failure "	✘"

      set -x tide_vi_mode_bg_color_default "normal"
      set -x tide_vi_mode_bg_color_insert "normal"
      set -x tide_vi_mode_bg_color_replace "normal"
      set -x tide_vi_mode_bg_color_visual "normal"
      set -x tide_vi_mode_color_default "white"
      set -x tide_vi_mode_color_insert "cyan"
      set -x tide_vi_mode_color_replace "green"
      set -x tide_vi_mode_color_visual "yellow"
      set -x tide_vi_mode_icon_default "D"
      set -x tide_vi_mode_icon_insert "I"
      set -x tide_vi_mode_icon_replace "R"
      set -x tide_vi_mode_icon_visual "V"

      set -x tide_prompt_add_newline_before "true"
      set -x tide_prompt_color_frame_and_connection "brblack"
      set -x tide_prompt_color_separator_same_color "brblack"
      set -x tide_prompt_icon_connection " "
      set -x tide_prompt_min_cols "34"
      set -x tide_prompt_pad_items "false"
      set -x tide_prompt_transient_enabled "false"

      set -x tide_left_prompt_frame_enabled "false"
      set -x tide_left_prompt_items pwd git jj newline character
      set -x tide_left_prompt_prefix ""
      set -x tide_left_prompt_separator_diff_color " "
      set -x tide_left_prompt_separator_same_color " "
      set -x tide_left_prompt_suffix " "

      set -x tide_right_prompt_frame_enabled "false"
      set -x tide_right_prompt_items status cmd_duration context jobs direnv time newline bun node python rustc java php pulumi ruby go gcloud kubectl distrobox toolbox terraform aws juju nix3_shell crystal elixir zig
      set -x tide_right_prompt_prefix " "
      set -x tide_right_prompt_separator_diff_color " "
      set -x tide_right_prompt_separator_same_color " "
      set -x tide_right_prompt_suffix ""

      set -x tide_pwd_bg_color "normal"
      set -x tide_pwd_color_anchors "brcyan"
      set -x tide_pwd_color_dirs "cyan"
      set -x tide_pwd_color_truncated_dirs "magenta"
      set -x tide_pwd_icon ""
      set -x tide_pwd_icon_home ""
      set -x tide_pwd_icon_unwritable ""
      set -x tide_pwd_markers .bzr .citc .git .hg .node-version .python-version .ruby-version .shorten_folder_marker .svn .terraform bun.lockb Cargo.toml composer.json CVS go.mod package.json build.zig

      set -x tide_cmd_duration_bg_color "normal"
      set -x tide_cmd_duration_color "brblack"
      set -x tide_cmd_duration_decimals "0"
      set -x tide_cmd_duration_icon ""
      set -x tide_cmd_duration_threshold "3000"

      set -x tide_context_always_display "false"
      set -x tide_context_bg_color "normal"
      set -x tide_context_color_default "yellow"
      set -x tide_context_color_root "bryellow"
      set -x tide_context_color_ssh "yellow"
      set -x tide_context_hostname_parts "1"

      set -x tide_shlvl_bg_color "normal"
      set -x tide_shlvl_color "yellow"
      set -x tide_shlvl_icon ""
      set -x tide_shlvl_threshold "1"

      set -x tide_git_bg_color "normal"
      set -x tide_git_bg_color_unstable "normal"
      set -x tide_git_bg_color_urgent "normal"
      set -x tide_git_color_branch "brgreen"
      set -x tide_git_color_conflicted "brred"
      set -x tide_git_color_dirty "bryellow"
      set -x tide_git_color_operation "brred"
      set -x tide_git_color_staged "bryellow"
      set -x tide_git_color_stash "brgreen"
      set -x tide_git_color_untracked "brblue"
      set -x tide_git_color_upstream "brgreen"
      set -x tide_git_icon ""
      set -x tide_git_truncation_length "24"
      set -x tide_git_truncation_strategy ""

      set -x tide_direnv_bg_color "normal"
      set -x tide_direnv_bg_color_denied "normal"
      set -x tide_direnv_color "bryellow"
      set -x tide_direnv_color_denied "brred"
      set -x tide_direnv_icon "▼"

      set -x tide_private_mode_bg_color "normal"
      set -x tide_private_mode_color "brwhite"
      set -x tide_private_mode_icon "󰗹"

      # Langs, tools

      set -x tide_aws_bg_color "normal"
      set -x tide_aws_color "yellow"
      set -x tide_aws_icon ""

      set -x tide_bun_bg_color "normal"
      set -x tide_bun_color "white"
      set -x tide_bun_icon "󰳓"

      set -x tide_crystal_bg_color "normal"
      set -x tide_crystal_color "brwhite"
      set -x tide_crystal_icon ""

      set -x tide_distrobox_bg_color "normal"
      set -x tide_distrobox_color "brmagenta"
      set -x tide_distrobox_icon "󰆧"

      set -x tide_docker_bg_color "normal"
      set -x tide_docker_color "blue"
      set -x tide_docker_default_contexts default colima
      set -x tide_docker_icon ""

      set -x tide_elixir_bg_color "normal"
      set -x tide_elixir_color "magenta"
      set -x tide_elixir_icon ""

      set -x tide_gcloud_bg_color "normal"
      set -x tide_gcloud_color "blue"
      set -x tide_gcloud_icon "󰊭"

      set -x tide_go_bg_color "normal"
      set -x tide_go_color "brcyan"
      set -x tide_go_icon ""

      set -x tide_java_bg_color "normal"
      set -x tide_java_color "yellow"
      set -x tide_java_icon ""

      set -x tide_jobs_bg_color "normal"
      set -x tide_jobs_color "green"
      set -x tide_jobs_icon ""
      set -x tide_jobs_number_threshold "1000"

      set -x tide_kubectl_bg_color "normal"
      set -x tide_kubectl_color "blue"
      set -x tide_kubectl_icon "󱃾"

      set -x tide_nix3_shell_bg_color "normal"
      set -x tide_nix3_shell_color "brblue"
      set -x tide_nix3_shell_icon ""

      set -x tide_juju_bg_color "normal"
      set -x tide_juju_color "yellow"
      set -x tide_juju_icon ""

      set -x tide_node_bg_color "normal"
      set -x tide_node_color "green"
      set -x tide_node_icon ""

      set -x tide_os_bg_color "normal"
      set -x tide_os_color "brwhite"
      set -x tide_os_icon ""

      set -x tide_php_bg_color "normal"
      set -x tide_php_color "blue"
      set -x tide_php_icon ""

      set -x tide_pulumi_bg_color "normal"
      set -x tide_pulumi_color "yellow"
      set -x tide_pulumi_icon ""

      set -x tide_python_bg_color "normal"
      set -x tide_python_color "cyan"
      set -x tide_python_icon "󰌠"

      set -x tide_ruby_bg_color "normal"
      set -x tide_ruby_color "red"
      set -x tide_ruby_icon ""

      set -x tide_rustc_bg_color "normal"
      set -x tide_rustc_color "red"
      set -x tide_rustc_icon ""

      set -x tide_terraform_bg_color "normal"
      set -x tide_terraform_color "magenta"
      set -x tide_terraform_icon "󱁢"

      set -x tide_time_bg_color "normal"
      set -x tide_time_color "brblack"
      set -x tide_time_format "%T"

      set -x tide_toolbox_bg_color "normal"
      set -x tide_toolbox_color "magenta"
      set -x tide_toolbox_icon ""

      set -x tide_zig_bg_color "normal"
      set -x tide_zig_color "yellow"
      set -x tide_zig_icon ""
    '';
    functions = {
      _tide_item_juju = /* fish */ ''
        if not command -sq juju
          return 1
        end
        set whoami (juju whoami 2>/dev/null | cut -d ':' -f2 | string trim)
        if test $status -ne 0
            return 1
        end
        _tide_print_item juju $tide_juju_icon' ' "$whoami[1]@$whoami[2]"
      '';
      # Improved nix shell
      _tide_item_nix3_shell = /* fish */ ''
        set packages (nix-inspect)
        if test -n "$IN_NIX_SHELL"
          set -q name; or set name nix-shell
          set -p packages $name
        end
        if set -q packages[1] &>/dev/null
          _tide_print_item nix3_shell $tide_nix3_shell_icon' ' " $(string shorten -m 40 "$packages")"
        end
      '';
      # Prompt item for jujutsu VCS
      _tide_item_jj = /* fish */ ''
        if not command -sq jj; or not jj root --quiet &>/dev/null
            return 1
        end

        set jj_status (jj log -r@ -n1 --ignore-working-copy --no-graph --color always -T '
          separate(" ",
            bookmarks.map(|x| if(
              x.name().substr(0, 10).starts_with(x.name()),
              x.name().substr(0, 10),
              x.name().substr(0, 9) ++ "…")
            ).join(" "),
            tags.map(|x| if(
              x.name().substr(0, 10).starts_with(x.name()),
              x.name().substr(0, 10),
              x.name().substr(0, 9) ++ "…")
            ).join(" "),
            surround("\"","\"",
              if(
                description.first_line().substr(0, 24).starts_with(description.first_line()),
                description.first_line().substr(0, 24),
                description.first_line().substr(0, 23) ++ "…"
              )
            ),
            change_id.shortest(),
            commit_id.shortest(),
            if(empty, "(empty)"),
            if(conflict, "(conflict)"),
            if(divergent, "(divergent)"),
            if(hidden, "(hidden)"),
          )
        ' | string trim)
        _tide_print_item jj $tide_jj_icon' ' (
            set_color black; echo -ns '('
            set_color normal; echo -ns "$(string join ', ' $jj_status)"
            set_color black; echo -ns ')'
        )
      '';
    };
  };
}
