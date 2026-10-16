{
  php,
  fetchgit,
  lessc,
  roundcube,
  ...
}:
php.buildComposerProject2 (finalAttrs: {
  pname = "kolab-plugins";
  version = "2025-12-08";

  src = fetchgit {
    url = "https://git.kolab.org/diffusion/RPK";
    rev = "2bc08b75ca47fa385310d7c94397ce1e49469aa6";
    hash = "sha256-zJMkdeSg1NSn3U9SZb3TviwcPjx10vQpnbM+E61RAQ8=";
  };

  patches = [
    ./priorities.patch
    ./color-tweaks.patch
    ./darkmode-fixes.patch
    ./plugin-vendor-load.patch
  ];

  composerVendor = php.mkComposerVendor {
    inherit (finalAttrs) pname src version;
    # Rename composer file
    postUnpack = ''
      mv $sourceRoot/composer.json-dist $sourceRoot/composer.json
    '';
    composerLock = ./composer.lock;
    composerNoDev = true;
    composerNoPlugins = true;
    composerNoScripts = true;
    strictDeps = true;
    vendorHash = "sha256-QpA4dCoE7Fd1eTsXPim8eAuvRNdX9HjGLqF0mpCvLtw=";
    postInstall = ''
      # Cleanup .git directories from git dependencies
      rm -rf $out/vendor/**/*/.git
    '';
  };

  nativeBuildInputs = [lessc];
  postBuild = ''
    ln -s ${roundcube}/skins .
    lessc --relative-urls -x plugins/libkolab/skins/elastic/libkolab.less > plugins/libkolab/skins/elastic/libkolab.min.css
    unlink skins
  '';

  postInstall = ''
    mkdir -p $out/plugins
    for plugin in $out/share/php/kolab-plugins/plugins/*; do
      ln -s $out/share/php/kolab-plugins/vendor $plugin/
      ln -s $plugin $out/plugins/
    done
  '';
})
