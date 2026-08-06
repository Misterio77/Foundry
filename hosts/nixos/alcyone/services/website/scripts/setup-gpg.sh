#!/bin/sh

pgp_id="7088C7421873E0DB97FF17C2245CAB70B4C225E9"
ssh_keygrip="149F16412997785363112F3DBD713BC91D51B831"

set -eu

check_bin() {
  if ! which "$1" > /dev/null; then
      echo "'$1' is not available" >&2
      exit 1
  fi
}

check_bin gpg
check_bin pinentry
echo "GPG and Pinentry located" >&2

if ! gpg -k "$pgp_id" > /dev/null 2> /dev/null; then
  echo "Downloading public key" >&2
  gpg --receive-keys "$pgp_id"
fi
if ! gpg -K "$pgp_id" > /dev/null 2> /dev/null; then
  echo "Searching card for private keystubs" >&2
  gpg --card-status
fi

if ! grep -q "pinentry-program" ~/.gnupg/gpg-agent.conf 2>/dev/null; then
  echo "pinentry-program $(readlink -f "$(which pinentry)")" >> ~/.gnupg/gpg-agent.conf
fi
if ! grep -q "enable-ssh-support" ~/.gnupg/gpg-agent.conf 2>/dev/null; then
  echo "enable-ssh-support" >> ~/.gnupg/gpg-agent.conf
fi
if ! grep -q "$ssh_keygrip" ~/.gnupg/sshcontrol 2>/dev/null; then
  echo "$ssh_keygrip" >> ~/.gnupg/sshcontrol
fi

echo "GPG configured" >&2

gpgconf --kill gpg-agent
gpgconf --launch gpg-agent
gpg-connect-agent updatestartuptty /bye

echo "GPG Agent restarted" >&2

export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
echo "SSH socket set" >&2
