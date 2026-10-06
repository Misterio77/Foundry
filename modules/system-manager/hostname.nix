# Expose the NixOS hostname interface to system and Home Manager modules.
# Metadata only: Ubuntu remains responsible for setting the actual hostname.
{lib, ...}: {
  options.networking.hostName = lib.mkOption {
    type = lib.types.str;
    example = "electra";
    description = ''
      The hostname used by this system's configuration.
      This option does not change the operating system's hostname.
    '';
  };
}
