{
  lib,
  stdenv,
  tree-sitter,
  nodejs,
}:
stdenv.mkDerivation {
  pname = "tree-sitter-todomd";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./grammar.js
      ./tree-sitter.json
      ./queries
      ./test
    ];
  };

  nativeBuildInputs = [tree-sitter nodejs];

  buildPhase = ''
    runHook preBuild
    tree-sitter generate --abi 14
    $CC -shared -fPIC -I src src/parser.c -o todomd.so
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    export HOME=$TMPDIR
    tree-sitter test
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 todomd.so $out/lib/todomd.so
    mkdir -p $out/queries
    cp queries/*.scm $out/queries/
    runHook postInstall
  '';

  meta = {
    description = "Tree-sitter highlighting for todomd task documents";
    license = lib.licenses.bsd2;
    platforms = lib.platforms.unix;
  };
}
