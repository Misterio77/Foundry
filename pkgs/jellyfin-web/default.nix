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
    patches = (old.patches or []) ++ [./quick-connect-qr.patch ./logout.patch];
    postPatch =
      (old.postPatch or "")
      + ''
        cp ${qrGenerator}/qrcode.js src/scripts/qrcode.cjs
        cp ${./quick-connect-qr.mjs} src/scripts/foundryQuickConnect.js
        substituteInPlace src/strings/en-us.json \
          --replace-fail '"ButtonUseQuickConnect": "Use Quick Connect"' '"ButtonUseQuickConnect": "Entrar com outro dispositivo"' \
          --replace-fail '"QuickConnectAuthorizeCode": "Enter code {0} to login"' '"QuickConnectAuthorizeCode": "Ou visite https://media.m7.rs/connect e digite {0}"'
        substituteInPlace src/strings/pt-br.json \
          --replace-fail '"ButtonUseQuickConnect": "Usar Quick Connect"' '"ButtonUseQuickConnect": "Entrar com outro dispositivo"' \
          --replace-fail '"QuickConnectAuthorizeCode": "Inserir código {0} para entrar"' '"QuickConnectAuthorizeCode": "Ou visite https://media.m7.rs/connect e digite {0}"'
      '';
    preBuild =
      (old.preBuild or "")
      + ''
        mkdir -p "$TMPDIR/foundry-qr-tests"
        cp ${./quick-connect-qr.mjs} "$TMPDIR/foundry-qr-tests/quick-connect-qr.mjs"
        cp ${./quick-connect-qr.test.mjs} "$TMPDIR/foundry-qr-tests/quick-connect-qr.test.mjs"
        cp ${qrGenerator}/qrcode.js "$TMPDIR/foundry-qr-tests/qrcode.cjs"
        node --test "$TMPDIR/foundry-qr-tests/quick-connect-qr.test.mjs"
        JELLYFIN_DASHBOARD_SOURCE="$PWD/src/utils/dashboard.js" node --test ${./logout.test.mjs}
      '';
  })
