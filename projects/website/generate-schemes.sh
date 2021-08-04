#!/usr/bin/env nix-shell
#! nix-shell -p flavours nodePackages.prettier -i bash

read -r -d '' schemes_source << END
apprentice: https://github.com/casonadams/base16-apprentice-scheme
atelier: https://github.com/atelierbram/base16-atelier-schemes
atlas: https://github.com/ajlende/base16-atlas-scheme
black-metal: https://github.com/metalelf0/base16-black-metal-scheme
blueish: https://github.com/TheMayoras/base16-blueish-scheme
brushtrees: https://github.com/WhiteAbeLincoln/base16-brushtrees-scheme
circus: https://github.com/stepchowfun/base16-circus-scheme
classic: https://github.com/detly/base16-classic-scheme
codeschool: https://github.com/blockloop/base16-codeschool-scheme
colors: https://github.com/hakatashi/base16-colors-scheme
cupertino: https://github.com/Defman21/base16-cupertino
danqing: https://github.com/CosmosAtlas/base16-danqing-scheme
darcula: https://github.com/casonadams/base16-darcula-scheme
darkmoss: https://github.com/avanzzzi/base16-darkmoss-scheme
darkviolet: https://github.com/ruler501/base16-darkviolet-scheme
default: https://github.com/chriskempson/base16-default-schemes
dirtysea: https://github.com/tartansandal/base16-dirtysea-scheme
dracula: https://github.com/dracula/base16-dracula-scheme
equilibrium: https://github.com/carloabelli/base16-equilibrium-scheme
espresso: https://github.com/alexmirrington/base16-espresso-scheme
eva: https://github.com/kjakapat/base16-eva-scheme
framer: https://github.com/jssee/base16-framer-scheme
fruit-soda: https://github.com/jozip/base16-fruit-soda-scheme
gigavolt: https://github.com/Whillikers/base16-gigavolt-scheme
github: https://github.com/Defman21/base16-github-scheme
gruvbox: https://github.com/dawikur/base16-gruvbox-scheme
gruvbox-material: https://github.com/MayushKumar/base16-gruvbox-material-scheme
hardcore: https://github.com/callerc1/base16-hardcore-scheme
heetch: https://github.com/tealeg/base16-heetch-scheme
helios: https://github.com/reyemxela/base16-helios-scheme
horizon: https://github.com/michael-ball/base16-horizon-scheme
humanoid: https://github.com/humanoid-colors/base16-humanoid-schemes
ia: https://github.com/aramisgithub/base16-ia-scheme
icy: https://github.com/icyphox/base16-icy-scheme
katy: https://github.com/gessig/base16-katy-scheme
kimber: https://github.com/akhsiM/base16-kimber-scheme
limelight: https://github.com/limelier/base16-limelight-scheme
materia: https://github.com/Defman21/base16-materia
material-vivid: https://github.com/joshyrobot/base16-material-vivid-scheme
materialtheme: https://github.com/ntpeters/base16-materialtheme-scheme
mellow: https://github.com/gidsi/base16-mellow-scheme
mexico-light: https://github.com/drzel/base16-mexico-light-scheme
nebula: https://github.com/Misterio77/base16-nebula-scheme
nord: https://github.com/spejamchr/base16-nord-scheme
nova: https://github.com/gessig/base16-nova-scheme
one-light: https://github.com/purpleKarrot/base16-one-light-scheme
onedark: https://github.com/tilal6991/base16-onedark-scheme
outrun: https://github.com/hugodelahousse/base16-outrun-schemes
pandora: https://github.com/PandorasFox/base16-pandora-scheme
pasque: https://github.com/Misterio77/base16-pasque-scheme
pinky: https://github.com/b3nj5m1n/base16-pinky-scheme
porple: https://github.com/AuditeMarlow/base16-porple-scheme
primer: https://github.com/jmlntw/base16-primer-scheme
purpledream: https://github.com/archmalet/base16-purpledream-scheme
qualia: https://github.com/isaacwhanson/base16-qualia-scheme
rebecca: https://github.com/vic/base16-rebecca
rose-pine: https://github.com/edunfelt/base16-rose-pine-scheme
sagelight: https://github.com/cveldy/base16-sagelight-scheme
sakura: https://github.com/Misterio77/base16-sakura-scheme
sandcastle: https://github.com/gessig/base16-sandcastle-scheme
silk: https://github.com/misterio77/base16-silk-scheme
snazzy: https://github.com/h404bi/base16-snazzy-scheme
solarflare: https://github.com/mnussbaum/base16-solarflare-scheme
solarized: https://github.com/aramisgithub/base16-solarized-scheme
spaceduck: https://github.com/Misterio77/base16-spaceduck-scheme
stella: https://github.com/Shrimpram/base16-stella-scheme
summercamp: https://github.com/zoefiri/base16-summercamp
summerfruit: https://github.com/cscorley/base16-summerfruit-scheme
synth-midnight: https://github.com/michael-ball/base16-synth-midnight-scheme
tender: https://github.com/DanManN/base16-tender-scheme
tomorrow: https://github.com/chriskempson/base16-tomorrow-scheme
twilight: https://github.com/hartbit/base16-twilight-scheme
unikitty: https://github.com/joshwlewis/base16-unikitty
uwunicorn: https://github.com/Misterio77/base16-uwunicorn-scheme
vice: https://github.com/Thomashighbaugh/base16-vice-scheme
vulcan: https://github.com/andreyvpng/base16-vulcan-scheme
windows: https://github.com/C-Fergus/base16-windows-scheme
woodland: https://github.com/jcornwall/base16-woodland-scheme
xcode-dusk: https://github.com/gonsie/base16-xcode-dusk-scheme
zenburn: https://github.com/elnawe/base16-zenburn-scheme

unclaimed: https://github.com/chriskempson/base16-unclaimed-schemes
END

rm ~/.local/share/flavours/base16/schemes -r
mkdir -p ~/.local/share/flavours/base16/sources/schemes
echo "$schemes_source" > ~/.local/share/flavours/base16/sources/schemes/list.yaml
flavours -v update schemes


read -r -d '' template_contents << END
/* {{{scheme-name}}} by {{{scheme-author}}} */

:root {
  --base00: #{{base00-hex}};
  --base01: #{{base01-hex}};
  --base02: #{{base02-hex}};
  --base03: #{{base03-hex}};
  --base04: #{{base04-hex}};
  --base05: #{{base05-hex}};
  --base06: #{{base06-hex}};
  --base07: #{{base07-hex}};
  --base08: #{{base08-hex}};
  --base09: #{{base09-hex}};
  --base0A: #{{base0A-hex}};
  --base0B: #{{base0B-hex}};
  --base0C: #{{base0C-hex}};
  --base0D: #{{base0D-hex}};
  --base0E: #{{base0E-hex}};
  --base0F: #{{base0F-hex}};
}
END

datalist_file="_includes/scheme-datalist.html"

# Add datalist opening tag
echo -n "<datalist id=\"scheme-list\">" > $datalist_file
# Remove all schemes
rm assets/schemes/*.css

# For each scheme
flavours list -l | while read slug; do
    # Get scheme file path
    scheme_path=$(flavours info $slug | head -1 | cut -d '@' -f2)
    # Build scheme
    flavours build $scheme_path <( echo "$template_contents" ) > assets/schemes/$slug.css
    # Add entry to datalist
    echo -n "<option>$slug</option>" >> $datalist_file
done
# Add datalist closing tag
echo "</datalist>" >> $datalist_file

# Prettify
prettier $datalist_file > /tmp/scheme-datalist.html
mv /tmp/scheme-datalist.html $datalist_file
