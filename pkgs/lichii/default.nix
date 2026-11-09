{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  cmake,
  ninja,
  pkg-config,
  python3,
  glslang,
  qt6,
  wrapGAppsHook3,
  boost,
  cpp-jwt,
  cubeb,
  eden,
  enet,
  ffmpeg-headless,
  fmt,
  frozen-containers,
  gamemode,
  httplib,
  kdePackages,
  libopus,
  libusb1,
  lz4,
  nlohmann_json,
  oaknut,
  openssl,
  pipewire,
  sdl3,
  simpleini,
  sirit,
  spirv-headers,
  unordered_dense,
  vulkan-headers,
  vulkan-loader,
  vulkan-memory-allocator,
  vulkan-utility-libraries,
  xbyak,
  zlib,
}: let
  bundled = {
    zbic = fetchurl {
      url = "https://github.com/kinnay/zbic/archive/11b08f2712264bbed731545085cbd9702096ceb7.tar.gz";
      sha512 = "fbe2f37986377d7f0d96ae3224c80b5971df6e8b6961f68061f1975ebb2e8cb78f07b90f014b007be4023dbf5513581504e7f7d61a5237cb2a8a7a61ae11e482";
    };
    reshade = fetchurl {
      url = "https://github.com/crosire/reshade/archive/v6.8.0.tar.gz";
      sha512 = "6fc9b39821ca6e2d91160f05846b3a42159fec759f5d6fba91d1a57801a1bdaf6047740578c136f0b1a60a9c29ad160d87dbfe0dbfbcdf6ea879a8a078377b8c";
    };
    # Upstream pins zstd to keep NUP archives byte-identical across platforms.
    zstd = fetchurl {
      url = "https://github.com/facebook/zstd/archive/33618c8.tar.gz";
      sha512 = "2b006c3c110c38bd2f5896b42d36a38931c8eae261f30552f9a9fd04458d218d8f1a1425f117fd12af545ed77042e4b2d1a1a9b6286c4d0b9d74ef79f20a8f08";
    };
  };
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "lichii";
    version = "125";

    src = fetchFromGitHub {
      owner = "zortos293";
      repo = "Lichii";
      tag = "build-${finalAttrs.version}";
      hash = "sha256-kHXFnYkvuNjorCKvfhvMI9x12hfpUx4OeTVtEo1GUqQ=";
    };

    strictDeps = true;

    nativeBuildInputs = [cmake ninja pkg-config python3 glslang qt6.qttools qt6.wrapQtAppsHook wrapGAppsHook3];
    buildInputs =
      [
        boost
        cpp-jwt
        cubeb
        enet
        ffmpeg-headless
        fmt
        frozen-containers
        gamemode
        httplib
        kdePackages.quazip
        libopus
        libusb1
        lz4
        nlohmann_json
        openssl
        qt6.qtbase
        qt6.qtcharts
        qt6.qtmultimedia
        qt6.qtwayland
        sdl3
        simpleini
        sirit
        spirv-headers
        unordered_dense
        vulkan-headers
        vulkan-memory-allocator
        vulkan-utility-libraries
        zlib
      ]
      ++ lib.optionals stdenv.hostPlatform.isx86_64 [xbyak]
      ++ lib.optionals stdenv.hostPlatform.isAarch64 [oaknut];

    postPatch =
      lib.concatStringsSep "\n" (lib.mapAttrsToList (name: src: ''
          mkdir -p .bundled/${name}
          tar xf ${src} -C .bundled/${name} --strip-components=1
        '')
        bundled)
      + ''
        patch -d .bundled/reshade -p1 < .patch/reshade/0001-from-chars-fallback.patch
      '';

    preConfigure = lib.concatStringsSep "\n" (map (name: ''
      cmakeFlagsArray+=("-D${name}_CUSTOM_DIR=$PWD/.bundled/${name}")
    '') (builtins.attrNames bundled));

    cmakeFlags =
      [
        (lib.cmakeBool "CPMUTIL_FORCE_SYSTEM" true)
        (lib.cmakeFeature "YUZU_TZDB_PATH" "${eden.nx_tzdb}")
        (lib.cmakeBool "ENABLE_WERROR" false)
        (lib.cmakeBool "ENABLE_UPDATE_CHECKER" false)
        (lib.cmakeBool "YUZU_DISABLE_LLVM" true)
        (lib.cmakeBool "ENABLE_QT_TRANSLATION" true)
        (lib.cmakeBool "YUZU_USE_QT_MULTIMEDIA" true)
        (lib.cmakeBool "YUZU_INSTALL_UDEV_RULES" true)
        (lib.cmakeBool "YUZU_TESTS" false)
        (lib.cmakeBool "BUILD_TESTING" false)
        (lib.cmakeFeature "LICHII_BUILD_TAG" "build-${finalAttrs.version}")
      ]
      ++ lib.concatMap (name: [
        (lib.cmakeBool "${name}_FORCE_BUNDLED" true)
      ]) (builtins.attrNames bundled);

    preFixup = ''
      qtWrapperArgs+=(--prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [vulkan-loader pipewire]})
    '';

    meta = {
      description = "Experimental Nintendo Switch and Switch 2 emulator";
      homepage = "https://github.com/zortos293/Lichii";
      license = lib.licenses.gpl3Plus;
      mainProgram = "lichii";
      platforms = ["x86_64-linux" "aarch64-linux"];
    };
  })
