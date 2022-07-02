{ stdenv, ruby, bundlerEnv, css-themes, python3Packages, dos2unix, perl }:

let
  gems = bundlerEnv {
    name = "misterio-me-env";
    inherit ruby;
    gemfile = ../Gemfile;
    lockfile = ../Gemfile.lock;
    gemset = ./gemset.nix;
  };
in
stdenv.mkDerivation {
  name = "misterio-me";
  src = ../.;

  JEKYLL_ENV = "production";

  buildInputs = [ gems ruby python3Packages.md2gemini dos2unix perl ];

  buildPhase = ''
    # Add themes
    mkdir src/assets/themes -p
    ln -s ${css-themes}/list.html -T src/_includes/scheme-datalist.html
    ln -s ${css-themes}/*.css -t src/assets/themes/

    # Convert markdown to gemtext, if needed
    shopt -s globstar
    for mdfile in src/**/*.md; do
      gmifile="''${mdfile/%.md/.gmi}"

      # Skip creating if gmi version already exists or if md does not have front matter
      if [ -f "$gmifile" ] || ! grep "\-\-\-" "$mdfile"; then
        continue
      fi

      # Grab front matter
      sed -n '/---/,/---/p' "$mdfile" > "$gmifile"

      # Turn markdown linebreaks into actual breaks, as well as link lists, so md2gemini respects it
      sed -E 's/(^\[.*\]\(.*\))(\s*\\+|\s\s+)$/\1\n/gm' "$mdfile" | \
      sed -E 's/^-\s+(\[.*\]\(.*\))$/\1\n/gm' | \
        md2gemini --frontmatter --links copy --plain --md-links >> "$gmifile"

      # Fix CRLF
      dos2unix "$gmifile"
      # Strip SVGs
      sed -Ei 's/\{% include icons\/.*\.svg %\}//g' "$gmifile"
      # Rewrite frontmatter containing .html permalinks into .gmi ones
      sed -Ei 's/(^permalink:.*)\.html/\1\.gmi/g' "$gmifile"
      # Rewrite relative .html links into .gmi
      sed -Ei 's/(^=>\s+\..*)\.html/\1\.gmi/g' "$gmifile"
      # Trim double newlines between links
      perl -0777 -pe 's/(^=>.*$)\n\n=>/\1\n=>/mg' -i "$gmifile"
      perl -0777 -pe 's/(^=>.*$)\n\n=>/\1\n=>/mg' -i "$gmifile"
    done

    ${gems}/bin/bundle exec jekyll build
  '';

  installPhase = ''
    mkdir -p $out
    cp -Tr _site $out/public
  '';
}
