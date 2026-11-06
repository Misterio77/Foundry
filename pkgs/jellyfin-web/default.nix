{
  fetchzip,
  jellyfin-web,
}: let
  qrGenerator = fetchzip {
    url = "https://registry.npmjs.org/qrcode-generator/-/qrcode-generator-1.4.4.tgz";
    hash = "sha256-ONLzg6Cc3zn2OFivSurZAbxQOQbtdtZdk/EtaJwLr84=";
  };
in
  jellyfin-web.overrideAttrs (old: {
    patches =
      (old.patches or [])
      ++ [./quick-connect-qr.patch ./quick-connect-helper.patch ./translations.patch ./gablogin-label.patch ./logout.patch ./oidc-login.patch ./session-expiry.patch ./session-expiry-tests.patch ./quick-connect-locales.patch ./oidc-logout.patch];
    # Webpack's locale import context also picks up patch backup files.
    patchFlags = (old.patchFlags or ["-p1"]) ++ ["--no-backup-if-mismatch"];
    postPatch =
      (old.postPatch or "")
      + ''
        cp ${qrGenerator}/qrcode.js src/scripts/qrcode.cjs
      '';
    doCheck = true;
    checkPhase = ''
      runHook preCheck
      npm test
      node --test scripts/test-oidc-logout.mjs
      runHook postCheck
    '';
  })
