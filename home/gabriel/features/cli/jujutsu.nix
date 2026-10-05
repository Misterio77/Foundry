{
  config,
  lib,
  pkgs,
  ...
}: let
  sshPublicKey = lib.trim (builtins.readFile ../../ssh.pub);
  allowedSigners = pkgs.writeText "jj-allowed-signers" ''
    ${config.programs.git.settings.user.email} namespaces="git" ${sshPublicKey}
  '';
  jjw = pkgs.writeShellApplication {
    name = "jjw";
    runtimeInputs = [pkgs.jujutsu];
    text = builtins.readFile ./jjw.sh;
  };
in {
  programs.jujutsu = {
    enable = true;
    settings = {
      user = {
        name = config.programs.git.settings.user.name;
        email = config.programs.git.settings.user.email;
      };
      ui = {
        pager = "less -FRX";
        show-cryptographic-signatures = true;
      };
      signing = {
        backend = "ssh";
        key = sshPublicKey;
        # Sign explicitly with jj sign; edits/rebases drop existing signatures.
        behavior = "drop";
        backends.ssh = {
          program = "${pkgs.openssh}/bin/ssh-keygen";
          allowed-signers = "${allowedSigners}";
        };
      };
      git.sign-on-push = false;
      revsets = {
        # Pick @ parents reachable from the nearest bookmarks.
        # Errors out if ambiguous, by design
        bookmark-advance-to = "@- & heads(::@ & bookmarks())::";
      };
      aliases = {
        tug = ["bookmark" "advance"];
      };
      template-aliases = {
        "gerrit_change_id(change_id)" = ''
          "Id0000000" ++ change_id.normal_hex()
        '';
      };
      templates = {
        draft_commit_description = ''
          concat(
            description,
            indent("JJ: ", concat(
              if(
                !description.contains("Change-Id: "),
                "Change-Id: " ++ gerrit_change_id(change_id) ++ "\n",
                "",
              ),
              "Change summary:\n",
              indent("     ", diff.summary()),
              "Full change:\n",
              "ignore-rest\n",
            )),
            diff.git(),
          )
        '';
      };
    };
  };

  home.packages = [
    jjw
    pkgs.jj-hunk-tool
  ];
}
