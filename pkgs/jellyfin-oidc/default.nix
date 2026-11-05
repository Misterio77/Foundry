{
  fetchzip,
  lib,
}:
fetchzip rec {
  pname = "jellyfin-oidc";
  version = "2.1.0.1";
  url = "https://github.com/aussierk/jellyfin-plugin-oidc/releases/download/v${version}/oidc-rbac.zip";
  hash = "sha256-EZ16RNEIzDgUCSH1GnDzYiWLUeHLhQyrhJygLXZjvTM=";
  stripRoot = false;
  meta = {
    description = "Jellyfin OIDC authentication plugin with stable identity mappings";
    homepage = "https://github.com/aussierk/jellyfin-plugin-oidc";
    license = lib.licenses.gpl3Plus;
    sourceProvenance = [lib.sourceTypes.binaryBytecode];
    platforms = lib.platforms.all;
  };
}
