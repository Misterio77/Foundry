{
  pkgs,
  config,
  lib,
  ...
}: let
  ssh = "${pkgs.openssh}/bin/ssh";

  git-m7 = pkgs.writeShellScriptBin "git-m7" ''
    case "''${1:-ls}" in
      ls)
        ${ssh} -TA git@m7.rs ls | grep '\.git$'
        ;;
      init)
        name="''${2:-$(basename "$PWD")}"
        ${ssh} -TA git@m7.rs << EOF
          git init --bare "$name.git"
          git -C "$name.git" branch -m main
    EOF
        git remote add origin git@m7.rs:"$name.git"
        ;;
      *)
        repo="$(git remote -v | grep git@m7.rs | head -1 | cut -d ':' -f2 | cut -d ' ' -f1)"
        if [[ "$repo" != *".git" ]]; then repo="$repo.git"; fi
        ${ssh} -TA git@m7.rs git -C "/srv/git/$repo" "$@"
        ;;
    esac
  '';
  # git commit --amend, but for older commits
  git-fixup = pkgs.writeShellScriptBin "git-fixup" ''
    rev="$(git rev-parse "$1")"
    git commit --fixup "$@"
    GIT_SEQUENCE_EDITOR=true git rebase -i --autostash --autosquash $rev^
  '';
in {
  home.packages = [
    git-m7
    git-fixup
  ];
  programs.git = {
    enable = true;
    package = pkgs.gitFull;
    signing = {
      format = "openpgp";
      signByDefault = false;
    };
    settings = {
      user = {
        name = "Gabriel Fontes";
        email = lib.mkDefault "hi@m7.rs";
      };
      aliases = {
        p = "pull --ff-only";
        ff = "merge --ff-only";
        graph = "log --decorate --oneline --graph";
        pushall = "!git remote | xargs -L1 git push --all";
        add-nowhitespace = "!git diff -U0 -w --no-color | git apply --cached --ignore-whitespace --unidiff-zero -";
      };
      init.defaultBranch = "main";
      gpg.program = "${config.programs.gpg.package}/bin/gpg2";

      merge.conflictStyle = "zdiff3";
      commit.verbose = true;
      diff.algorithm = "histogram";
      log.date = "iso";
      column.ui = "auto";
      branch.sort = "committerdate";
      # Automatically track remote branch
      push.autoSetupRemote = true;
      # Reuse merge conflict fixes when rebasing
      rerere.enabled = true;
    };
    lfs.enable = true;
    ignores = [
      ".direnv"
      "result"
      ".jj"
    ];
  };
}
