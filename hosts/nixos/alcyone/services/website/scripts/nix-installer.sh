#!/bin/sh

set -euo pipefail

arch="$(uname -m)"
job="https://hydra.nixos.org/job/nix/master/buildStatic.$arch-linux/latest/download-by-type/file/binary-dist"

dir="$HOME/.local/share/nix/bin"
mkdir -p "$dir"
if [ -f "$dir/nix" ]; then
    curl -L "$job" -o "$dir/nix" -z "$dir/nix"
else
    curl -L "$job" -o "$dir/nix"
fi
chmod +x "$dir/nix"

comment="# Added by misterio nix installer"

if ! grep -sq "$comment" "$HOME/.profile" ; then
    mkdir -p "$HOME/.config/nix"
    echo "$comment" >> "$HOME/.config/nix/nix.conf"
    echo 'experimental-features = nix-command flakes' >> "$HOME/.config/nix/nix.conf"
fi

if ! grep -sq "$comment" "$HOME/.profile" ; then
    echo "$comment" >> "$HOME/.profile"
    echo "export PATH=\"$dir:\$PATH\"" >> "$HOME/.profile"
    echo >&2 "The directory '$dir' has been added to your PATH variable on '~/.profile'."
    echo >&2 "Re-login or do 'source ~/.profile' to update it."
fi
