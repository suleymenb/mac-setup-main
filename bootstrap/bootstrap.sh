#!/usr/bin/env bash
# bootstrap-mac-ansible.sh
# 1) Installs Xcode Command Line Tools (manual popup if missing)
# 2) Installs Homebrew and configures PATH
# 3) Installs pipx and ansible-core
# 4) Clones your repo and runs ansible-playbook

set -euo pipefail

log() { printf "\n==> %s\n" "$1"; }

# --- 0) Xcode Command Line Tools ---
log "Checking Xcode Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then
  log "Installing Xcode Command Line Tools (GUI popup). Re-run this script after installation."
  xcode-select --install || true
  exit 1
fi

# --- 0b) Prime sudo ---
# Some casks (Docker Desktop) symlink helper binaries into /usr/local/bin and
# shell out to sudo themselves. Ansible gives them no terminal to prompt on, so
# we cache the credential up front and refresh it for as long as this script runs.
log "Asking for your macOS password once (needed for Docker Desktop and Homebrew)"
sudo -v
while true; do
  sudo -n true
  sleep 60
  kill -0 "$$" 2>/dev/null || exit
done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

# --- 1) Homebrew ---
log "Checking Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  log "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# --- 2) Configure Brew PATH (Apple Silicon vs Intel) ---
log "Configuring brew shellenv in ~/.zprofile"
BREW_SHELLENV_LINE=""

if [[ -x /opt/homebrew/bin/brew ]]; then
  BREW_SHELLENV_LINE='eval "$(/opt/homebrew/bin/brew shellenv)"'
elif [[ -x /usr/local/bin/brew ]]; then
  BREW_SHELLENV_LINE='eval "$(/usr/local/bin/brew shellenv)"'
else
  log "brew binary not found"
  exit 1
fi

touch "$HOME/.zprofile"
if ! grep -Fq "$BREW_SHELLENV_LINE" "$HOME/.zprofile"; then
  printf "\n%s\n" "$BREW_SHELLENV_LINE" >> "$HOME/.zprofile"
fi

# Apply to current session
# shellcheck disable=SC1090
eval "$BREW_SHELLENV_LINE"

# --- 3) pipx + ansible-core ---
log "Installing pipx"
brew install pipx
pipx ensurepath || true

# Ensure current session PATH includes pipx binaries
if [[ -d "$HOME/.local/bin" ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

log "Installing ansible-core via pipx"
if ! command -v ansible-playbook >/dev/null 2>&1; then
  pipx install ansible-core
fi

# --- 4) Run playbook ---
log "Installing required Ansible collections"
ansible-galaxy collection install -r requirements.yml

log "Running Ansible playbook"
ansible-playbook playbook.yml

# --- 5) Verify everything actually landed ---
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -x "$REPO_ROOT/verify.sh" ]]; then
  log "Verifying installation"
  "$REPO_ROOT/verify.sh" || log "Some checks failed — see the list above"
fi

log "Setup complete"
