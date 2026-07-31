#!/usr/bin/env bash
# verify.sh — post-run health check for the mac-setup playbook.
# Checks every single thing the playbook is supposed to install or configure.
# Exit code 0 = everything passed, 1 = at least one FAIL.

set -uo pipefail

PASS=0
FAIL=0
WARN=0
FAILED_ITEMS=()

if [[ -t 1 ]]; then
  G=$'\033[0;32m'; R=$'\033[0;31m'; Y=$'\033[0;33m'; B=$'\033[1m'; N=$'\033[0m'
else
  G=""; R=""; Y=""; B=""; N=""
fi

section() { printf "\n%s— %s —%s\n" "$B" "$1" "$N"; }

ok()   { printf "  %s✔%s %-34s %s\n" "$G" "$N" "$1" "${2:-}"; PASS=$((PASS+1)); }
bad()  { printf "  %s✘%s %-34s %s\n" "$R" "$N" "$1" "${2:-}"; FAIL=$((FAIL+1)); FAILED_ITEMS+=("$1"); }
warn() { printf "  %s!%s %-34s %s\n" "$Y" "$N" "$1" "${2:-}"; WARN=$((WARN+1)); }

# --- helpers -----------------------------------------------------------------

# check_cmd <label> <binary> [version-args...]
check_cmd() {
  local label="$1" bin="$2"; shift 2
  if command -v "$bin" >/dev/null 2>&1; then
    local v=""
    if [[ $# -gt 0 ]]; then
      v=$("$bin" "$@" 2>/dev/null | head -n1)
    fi
    ok "$label" "$v"
  else
    bad "$label" "not found on PATH"
  fi
}

check_formula() {
  local f="$1" label="${2:-$1}"
  if brew list --formula --versions "$f" >/dev/null 2>&1; then
    ok "$label" "$(brew list --formula --versions "$f" 2>/dev/null | head -n1)"
  else
    bad "$label" "brew formula not installed"
  fi
}

check_cask() {
  local c="$1" label="${2:-$1}"
  if brew list --cask --versions "$c" >/dev/null 2>&1; then
    ok "$label" "$(brew list --cask --versions "$c" 2>/dev/null | head -n1)"
  else
    bad "$label" "brew cask not installed"
  fi
}

check_dir() {
  local label="$1" path="$2"
  if [[ -d "$path" ]]; then ok "$label"; else bad "$label" "missing: $path"; fi
}

# check_zshrc <label> <grep-pattern>
check_zshrc() {
  local label="$1" pat="$2"
  if [[ -f "$HOME/.zshrc" ]] && grep -Eq "$pat" "$HOME/.zshrc"; then
    ok "$label"
  else
    bad "$label" "not found in ~/.zshrc"
  fi
}

check_default() {
  local label="$1" domain="$2" key="$3" expect="$4"
  local actual
  actual=$(defaults read "$domain" "$key" 2>/dev/null)
  if [[ "$actual" == "$expect" ]]; then
    ok "$label" "$key=$actual"
  else
    bad "$label" "$key=${actual:-<unset>} (expected $expect)"
  fi
}

printf "%smac-setup verification%s  —  %s\n" "$B" "$N" "$(date '+%Y-%m-%d %H:%M')"

# --- prerequisites -----------------------------------------------------------
section "Prerequisites"

if xcode-select -p >/dev/null 2>&1; then
  ok "Xcode Command Line Tools" "$(xcode-select -p)"
else
  bad "Xcode Command Line Tools" "run: xcode-select --install"
fi

if command -v brew >/dev/null 2>&1; then
  ok "Homebrew" "$(brew --version 2>/dev/null | head -n1)"
else
  bad "Homebrew" "not on PATH — everything below will fail"
  printf "\n%sHomebrew is missing. Fix that first, then re-run.%s\n" "$R" "$N"
  exit 1
fi

check_cmd "pipx"           pipx --version
check_cmd "ansible-core"   ansible --version
check_cmd "ansible-playbook" ansible-playbook --version

if ansible-galaxy collection list 2>/dev/null | grep -q 'community.general'; then
  ok "community.general collection"
else
  bad "community.general collection" "run: ansible-galaxy collection install -r requirements.yml"
fi

# --- terraform ---------------------------------------------------------------
section "Terraform"

if brew tap 2>/dev/null | grep -qx 'hashicorp/tap'; then
  ok "hashicorp/tap tapped"
else
  bad "hashicorp/tap tapped" "run: brew tap hashicorp/tap"
fi

if brew list --formula --versions terraform >/dev/null 2>&1 \
   || brew list --formula --versions hashicorp/tap/terraform >/dev/null 2>&1; then
  ok "terraform (brew)" "$(brew list --formula --versions terraform 2>/dev/null | head -n1)"
else
  bad "terraform (brew)" "not installed via brew"
fi

check_cmd "terraform binary"  terraform version
check_cmd "terraform-docs"    terraform-docs --version

# tflint lives in the terraform-linters tap, not homebrew-core
if command -v tflint >/dev/null 2>&1; then
  ok "tflint" "$(tflint --version 2>/dev/null | head -n1)"
else
  warn "tflint" "optional — brew install terraform-linters/tap/tflint"
fi

# terraform must actually run, not just exist
if command -v terraform >/dev/null 2>&1; then
  if terraform version >/dev/null 2>&1; then
    ok "terraform runs cleanly"
  else
    bad "terraform runs cleanly" "binary exists but exits non-zero"
  fi
fi

# --- docker ------------------------------------------------------------------
section "Docker"

check_cask "docker-desktop" "Docker Desktop"
check_dir "Docker.app present" "/Applications/Docker.app"
check_formula docker-compose

for f in lazydocker dive; do
  if brew list --formula --versions "$f" >/dev/null 2>&1; then
    ok "$f" "$(brew list --formula --versions "$f" 2>/dev/null | head -n1)"
  else
    warn "$f" "optional — not installed"
  fi
done

if command -v docker >/dev/null 2>&1; then
  ok "docker CLI" "$(docker --version 2>/dev/null)"
  if docker info >/dev/null 2>&1; then
    ok "docker daemon running"
  else
    warn "docker daemon running" "daemon not up — launch Docker Desktop"
  fi
else
  warn "docker CLI" "not on PATH — open Docker Desktop once to finish setup"
fi

# --- kubernetes --------------------------------------------------------------
section "Kubernetes"

check_formula kubernetes-cli "kubernetes-cli (kubectl)"
check_formula helm

for f in k9s kubectx minikube; do
  if brew list --formula --versions "$f" >/dev/null 2>&1; then
    ok "$f" "$(brew list --formula --versions "$f" 2>/dev/null | head -n1)"
  else
    warn "$f" "optional — not installed"
  fi
done

check_cmd "kubectl binary" kubectl version --client
check_cmd "helm binary"    helm version --short

check_zshrc "kubectl zsh block"  '^# BEGIN ANSIBLE_KUBECTL'
check_zshrc "alias k=kubectl"    "^alias k='kubectl'"

# --- cli tools ---------------------------------------------------------------
section "CLI tools"

check_formula eza
check_formula dust "dust (du-dust)"
check_formula vim
check_formula mc "mc (midnight commander)"
check_formula ansible-lint

check_cmd "eza binary"          eza --version
check_cmd "dust binary"         dust --version
check_cmd "vim binary"          vim --version
check_cmd "mc binary"           mc --version
check_cmd "ansible-lint binary" ansible-lint --version

# rust should be GONE per the TODO
if brew list --formula --versions rust >/dev/null 2>&1; then
  warn "rust removed" "still installed — run: brew uninstall rust"
else
  ok "rust removed"
fi

# --- applications ------------------------------------------------------------
section "Applications"

check_cask iterm2
check_cask rectangle
check_cask stats
check_cask zed

for app in iTerm Rectangle Stats Zed; do
  if [[ -d "/Applications/${app}.app" ]]; then
    ok "${app}.app present"
  else
    warn "${app}.app present" "not in /Applications"
  fi
done

# --- fonts -------------------------------------------------------------------
section "Fonts"

check_cask font-jetbrains-mono "JetBrains Mono"
check_cask font-meslo-lg-nerd-font "Meslo LG Nerd Font"

if ls "$HOME/Library/Fonts"/JetBrainsMono* >/dev/null 2>&1 \
   || ls /Library/Fonts/JetBrainsMono* >/dev/null 2>&1; then
  ok "JetBrains Mono font files"
else
  warn "JetBrains Mono font files" "no matching files in Font dirs"
fi

if ls "$HOME/Library/Fonts"/MesloLG* >/dev/null 2>&1 \
   || ls /Library/Fonts/MesloLG* >/dev/null 2>&1; then
  ok "Meslo LG Nerd font files"
else
  warn "Meslo LG Nerd font files" "no matching files in Font dirs"
fi

# --- zsh ---------------------------------------------------------------------
section "Zsh configuration"

check_dir "Oh My Zsh installed"        "$HOME/.oh-my-zsh"
check_dir "powerlevel10k theme"        "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
check_dir "zsh-autosuggestions"        "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
check_dir "zsh-syntax-highlighting"    "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"

if [[ -f "$HOME/.zshrc" ]]; then
  ok ".zshrc exists"
else
  bad ".zshrc exists" "missing"
fi

check_zshrc "export ZSH="              '^export ZSH='
check_zshrc "ZSH_THEME powerlevel10k"  '^ZSH_THEME="powerlevel10k/powerlevel10k"'
check_zshrc "plugins list"             '^plugins=\(git sudo zsh-autosuggestions zsh-syntax-highlighting\)'
check_zshrc "oh-my-zsh sourced"        '^source \$ZSH/oh-my-zsh\.sh'
check_zshrc "OMZ update settings"      '^# BEGIN ANSIBLE_OMZ_SETTINGS'
check_zshrc "aliases block"            '^# BEGIN ANSIBLE_ALIASES'
check_zshrc "alias rz"                 "^alias rz="
check_zshrc "alias ls -> eza"          '^alias ls="eza'
check_zshrc "alias ll -> eza"          '^alias ll="eza'
check_zshrc "p10k config sourced"      '\.p10k\.zsh'
check_zshrc "brew autoupdate block"    '^# BEGIN ANSIBLE_BREW_AUToupdates'

# cargo PATH should be gone now that rust is removed
if [[ -f "$HOME/.zshrc" ]] && grep -q '\.cargo/bin' "$HOME/.zshrc"; then
  warn "cargo PATH removed" "still referenced in ~/.zshrc"
else
  ok "cargo PATH removed"
fi

if [[ "${SHELL:-}" == *zsh ]]; then
  ok "login shell is zsh" "$SHELL"
else
  warn "login shell is zsh" "currently ${SHELL:-unknown}"
fi

# .zshrc must actually parse
if command -v zsh >/dev/null 2>&1; then
  if zsh -n "$HOME/.zshrc" 2>/dev/null; then
    ok ".zshrc syntax valid"
  else
    bad ".zshrc syntax valid" "zsh -n reported a syntax error"
  fi
fi

# --- system settings ---------------------------------------------------------
section "System settings"

check_default "Finder shows hidden files" com.apple.finder AppleShowAllFiles 1

if defaults read -g AppleInterfaceStyle 2>/dev/null | grep -qi dark; then
  ok "Dark mode enabled"
else
  bad "Dark mode enabled" "AppleInterfaceStyle is not Dark"
fi

# --- summary -----------------------------------------------------------------
printf "\n%s────────────────────────────────────────%s\n" "$B" "$N"
printf "  %spassed: %d%s   %swarnings: %d%s   %sfailed: %d%s\n" \
  "$G" "$PASS" "$N" "$Y" "$WARN" "$N" "$R" "$FAIL" "$N"

if (( FAIL > 0 )); then
  printf "\n%sFailed checks:%s\n" "$R" "$N"
  for item in "${FAILED_ITEMS[@]}"; do
    printf "  - %s\n" "$item"
  done
  printf "\nRe-run the playbook, or a single role:\n"
  printf "  ansible-playbook playbook.yml --tags terraform\n"
  exit 1
fi

printf "\n%sAll checks passed.%s\n" "$G" "$N"
exit 0
