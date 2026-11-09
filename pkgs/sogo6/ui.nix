{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
  nodejs_24,
}:
buildNpmPackage rec {
  pname = "sogo6-ui";
  version = "6.0.0-alpha2";
  src = fetchFromGitHub {
    owner = "Alinto";
    repo = "SOGo6-UI";
    rev = "v${version}";
    hash = "sha256-EtOUDj/tbFu2Ntoaa6dT22jlvfIDpMRZxnhzuiKcxCw=";
  };
  patches = [./ui.patch ./ui-dav.patch];
  postPatch = ''
    substituteInPlace \
      src/features/offline/auth/redirect-after-logout.ts \
      src/features/offline/auth/__tests__/redirect-after-logout.test.ts \
      src/components/ui/__tests__/header-dropdown.test.tsx \
      --replace-fail 'https://auth.m7.rs/application/o/sogo6-oidc-pilot/end-session/' \
        'https://auth.m7.rs/application/o/sogo/end-session/'
  '';
  nodejs = nodejs_24;
  npmDepsHash = "sha256-6W6JlbV/YMmO/ylAp0c7VHSbO3b+KTZGwZvq/X4UWz4=";
  nativeBuildInputs = [makeWrapper];
  env = {
    NEXT_TELEMETRY_DISABLED = "1";
    HUSKY = "0";
  };
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    npm test -- --runInBand --coverage=false \
      src/features/auth/components/__tests__/login-form.test.tsx \
      src/features/offline/auth/__tests__/redirect-after-logout.test.ts \
      src/components/ui/__tests__/header-dropdown.test.tsx \
      src/features/calendars/utils/__tests__/recurrence-scope-mutation.test.ts \
      src/features/user-settings/profile/components/__tests__/basic-info-tab.test.tsx \
      src/features/tasks/store/__tests__/dav-preconditions.test.ts \
      src/features/tasks/hooks/__tests__/use-task-selection.test.ts \
      src/features/tasks/components/__tests__/task-form.test.tsx \
      src/features/calendars/components/__tests__/event-form.test.tsx \
      src/features/address_books/components/__tests__/contact-form.test.tsx \
      src/features/address_books/components/visualization/__tests__/note-field.test.tsx \
      src/features/user-profile/hooks/__tests__/dav-capabilities.test.ts \
      src/features/calendars/utils/__tests__/is-calendar-writable.test.ts \
      src/features/calendars/components/sidebar/__tests__/sidebar.test.tsx \
      src/features/calendars/components/sidebar/__tests__/sidebar-item.test.tsx \
      src/features/address_books/components/sidebar/__tests__/sidebar.test.tsx \
      src/features/address_books/components/sidebar/__tests__/sidebar-item.test.tsx \
      src/features/address_books/components/visualization/__tests__/entry-actions-shell.test.tsx \
      src/features/address_books/components/visualization/__tests__/contact-actions.test.tsx \
      src/features/address_books/components/visualization/__tests__/distribution-list-actions.test.tsx \
      src/features/address_books/components/__tests__/list.test.tsx \
      src/features/address_books/components/__tests__/distribution-list-form-host.test.tsx \
      src/hooks/__tests__/use-cross-module-create-actions.test.ts
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/sogo6-ui/.next/cache" "$out/bin"
    cp -r .next/standalone/. "$out/share/sogo6-ui/"
    cp -r .next/static "$out/share/sogo6-ui/.next/"
    cp -r public "$out/share/sogo6-ui/"
    mkdir -p "$out/share/sogo6-ui/src"
    cp -r src/messages "$out/share/sogo6-ui/src/"
    makeWrapper ${lib.getExe nodejs_24} "$out/bin/sogo6-ui" \
      --set NODE_ENV production \
      --set NEXT_TELEMETRY_DISABLED 1 \
      --add-flags "$out/share/sogo6-ui/server.js"
    runHook postInstall
  '';
  meta = {
    description = "SOGo 6 web UI with Foundry OIDC and direct-DAV integration";
    homepage = "https://github.com/Alinto/SOGo6-UI";
    license = lib.licenses.gpl3Plus;
    mainProgram = "sogo6-ui";
    platforms = lib.platforms.linux;
  };
}
