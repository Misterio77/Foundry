{config, lib, ...}: {
  programs.todoman = {
    enable = true;
    glob = "*/*";
    extraConfig = let
      mainAccount = config.accounts.calendar.accounts.personal or {};
      defaultList = mainAccount.primaryCollection or null;
    in ''
      ${lib.optionalString (defaultList != null) ''default_list = "${defaultList}"''}
      date_format = "%d/%m/%Y"
      time_format = "%H:%M"
      humanize = True
      default_due = 0
    '';
  };
  programs.fish.interactiveShellInit = /* fish */ ''
    complete -xc todo -a '(__fish_complete_bash)'
  '';
}
