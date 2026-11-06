{
  runCommand,
  postgresql_14,
  pythonEnv,
  blueprints,
}:
runCommand "authentik-password-guessing-test"
{
  nativeBuildInputs = [postgresql_14 pythonEnv];
}
''
  export HOME="$TMPDIR"
  export PGHOST="$TMPDIR" PGUSER=authentik PGDATABASE=authentik
  initdb -D "$TMPDIR/db" -U "$PGUSER" --auth=trust --no-locale > /dev/null
  pg_ctl -D "$TMPDIR/db" -l "$TMPDIR/postgres.log" \
    -o "-k $PGHOST -c listen_addresses= -F" -w start
  trap 'pg_ctl -D "$TMPDIR/db" -m immediate stop' EXIT
  createdb

  export DJANGO_SETTINGS_MODULE=authentik.root.settings
  export AUTHENTIK_SECRET_KEY=isolated-password-guessing-test
  export AUTHENTIK_POSTGRESQL__HOST="$PGHOST"
  export AUTHENTIK_POSTGRESQL__USER="$PGUSER"
  export AUTHENTIK_POSTGRESQL__NAME="$PGDATABASE"
  export AUTHENTIK_BLUEPRINTS_DIR=${blueprints}
  export AUTHENTIK_REPUTATION__EXPIRY=900
  export AUTHENTIK_ERROR_REPORTING__ENABLED=false
  export AUTHENTIK_LOG_LEVEL=warning

  python ${./password-guessing.py}
  touch "$out"
''
