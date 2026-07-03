{config, lib, ...}: {
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
      signing = let
        gitCfg = config.programs.git.settings;
      in {
        backend = "gpg";
        behaviour = if gitCfg.commit.gpgSign then "own" else "never";
        key = gitCfg.user.signing.key;
      };
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
}
