{ stdenv, ruby, bundlerEnv, css-themes, python3Packages, dos2unix }:

let
  gems = bundlerEnv {
    name = "misterio-me-env";
    inherit ruby;
    gemdir = ./.;
  };
in
stdenv.mkDerivation {
  name = "misterio-me";
  src = ./.;

  JEKYLL_ENV = "production";

  buildInputs = [ gems ruby python3Packages.md2gemini dos2unix ];

  buildPhase = ''
    # Add themes
    mkdir _main/assets/themes -p
    cp ${css-themes}/list.html _main/_includes/scheme-datalist.html
    cp -r ${css-themes}/*.css _main/assets/themes/

    # Convert markdown to gemtext, if needed
    shopt -s globstar
    for mdfile in _main/**/*.md; do
      gmifile="''${mdfile/%.md/.gmi}"

      # Skip creating if gmi version already exists or if md does not have front matter
      if [ -f "$gmifile" ] || ! grep "\-\-\-" "$mdfile"; then
        continue
      fi

      # Grab front matter
      sed -n '/---/,/---/p' "$mdfile" > "$gmifile"
      # Convert
      md2gemini "$mdfile" \
        --frontmatter --links copy --plain --md-links >> "$gmifile"
      # Fix CRLF
      dos2unix "$gmifile"
      # Strip SVGs
      sed -ri 's@\{% include icons/.*\.svg %\}@@g' "$gmifile"
    done

    ${gems}/bin/bundle exec jekyll build
  '';

  installPhase = ''
    mkdir -p $out
    cp -Tr _site $out/public
  '';
}
