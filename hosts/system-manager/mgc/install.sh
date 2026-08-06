#!/usr/bin/env bash
set -euo pipefail

readonly target_user="gabriel"
readonly target_home="/home/$target_user"
readonly repo_dir="${FOUNDRY_DIR:-$target_home/Foundry}"
activate=false

usage() {
  cat <<'EOF'
Bootstrap mgc from a fresh Ubuntu Server installation.

Usage: install.sh [--activate]

The first run installs Ubuntu prerequisites and multi-user Nix, then prints
mgc's age recipient. It expects Foundry at ~/Foundry; set FOUNDRY_DIR to use a
different checkout. Add the recipient to .sops.yaml and rekey hosts/secrets.yaml
from an already-authorized machine before activating.

Run again with --activate after updating the checkout on mgc.
EOF
}

while (($#)); do
  case "$1" in
    --activate) activate=true ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if ((EUID == 0)); then
  echo "Run this script as $target_user, not root; it will use sudo when needed." >&2
  exit 1
fi

if [[ $(id -un) != "$target_user" ]]; then
  echo "This configuration expects the existing Ubuntu account to be named $target_user." >&2
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "Cannot identify the operating system." >&2
  exit 1
fi
# shellcheck disable=SC1091
source /etc/os-release
if [[ ${ID:-} != ubuntu ]]; then
  echo "mgc is supported on Ubuntu; found ${ID:-unknown}." >&2
  exit 1
fi

if [[ $(uname -m) != x86_64 ]]; then
  echo "mgc is configured for x86_64-linux; found $(uname -m)." >&2
  exit 1
fi

if [[ ! -f "$repo_dir/flake.nix" ]]; then
  echo "Foundry checkout not found at $repo_dir; clone or restore it first." >&2
  exit 1
fi

sudo -v

ubuntu_packages=(
  bluez
  brightnessctl
  ca-certificates
  curl
  dbus-user-session
  git
  libpam-systemd
  libspa-0.2-bluetooth
  openssh-client
  pcscd
  pipewire
  pipewire-pulse
  policykit-1
  policykit-1-gnome
  power-profiles-daemon
  rtkit
  upower
  wireplumber
  wpasupplicant
)

sudo env DEBIAN_FRONTEND=noninteractive apt-get update
sudo env DEBIAN_FRONTEND=noninteractive apt-get install --yes "${ubuntu_packages[@]}"

# sops-nix uses this key after its public recipient is added to .sops.yaml.
sudo ssh-keygen -A

if [[ -x /nix/nix-installer ]]; then
  cat >&2 <<'EOF'
A Determinate Nix installation already exists. Remove it before continuing:

  /nix/nix-installer uninstall
EOF
  exit 1
fi

if [[ ! -x /nix/var/nix/profiles/default/bin/nix ]]; then
  curl --proto '=https' --tlsv1.2 --fail --show-error --silent --location \
    https://nixos.org/nix/install \
    | sh -s -- --daemon
fi

# shellcheck disable=SC1091
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
# The upstream installer does not enable flakes; System Manager will persist
# these settings in /etc/nix/nix.conf during activation.
export NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG
}experimental-features = nix-command flakes"

recipient=$(
  nix shell nixpkgs#ssh-to-age --command ssh-to-age \
    < /etc/ssh/ssh_host_ed25519_key.pub
)

cat <<EOF

Ubuntu prerequisites and Nix are ready.

mgc age recipient:

  $recipient

On an already-authorized machine:
  1. Replace mgc's placeholder in .sops.yaml with this recipient.
  2. Uncomment mgc in the hosts/secrets.yaml creation rule.
  3. Run: sops updatekeys hosts/secrets.yaml
  4. Commit and push, then update $repo_dir on mgc.
EOF

if ! $activate; then
  cat <<EOF

After updating this checkout, finish with:

  $repo_dir/hosts/system-manager/mgc/install.sh --activate
EOF
  exit 0
fi

cat <<'EOF'

Activating mgc. Run this from a recoverable TTY: greetd will replace any existing
display manager, and the first Home Manager activation may back up dotfiles.
EOF

nix run --accept-flake-config "$repo_dir#system-manager" -- \
  switch --flake "$repo_dir#mgc" --sudo

cat <<'EOF'

Activation complete. Reboot to verify greetd, logind, graphics, audio, and the
Home Manager session from a clean boot.
EOF
