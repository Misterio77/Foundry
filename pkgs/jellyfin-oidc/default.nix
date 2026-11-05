{
  buildDotnetModule,
  dotnetCorePackages,
  fetchFromGitHub,
  lib,
}:
buildDotnetModule rec {
  pname = "jellyfin-oidc";
  version = "2.1.0.1";

  src = fetchFromGitHub {
    owner = "aussierk";
    repo = "jellyfin-plugin-oidc";
    tag = "v${version}";
    hash = "sha256-gY4i4e/LAZil0wz6z4IJxv9v5ndG5AahiXfhomC11G8=";
  };
  patches = [./device-code.patch ./device-code-tests.patch ./localization.patch];

  projectFile = "Jellyfin.Plugin.OIDC/Jellyfin.Plugin.OIDC.csproj";
  testProjectFile = "Jellyfin.Plugin.OIDC.Tests/Jellyfin.Plugin.OIDC.Tests.csproj";
  nugetDeps = ./deps.json;
  dotnet-sdk = dotnetCorePackages.sdk_10_0;
  dotnet-runtime = dotnetCorePackages.aspnetcore_10_0;
  doCheck = true;
  executables = [];
  installPath = builtins.placeholder "out";

  meta = {
    description = "Jellyfin OIDC authentication plugin with device-code approval links";
    homepage = "https://github.com/aussierk/jellyfin-plugin-oidc";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
