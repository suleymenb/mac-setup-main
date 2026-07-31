# Mac Setup – Fully Automated macOS Bootstrap with Ansible

This repository provides a fully automated macOS setup using Ansible.
It installs Homebrew, development tools, Rust, Zsh configuration, and preferred applications
in a reproducible and idempotent way.

---

## 1. Requirements

- macOS
- Internet connection
- Xcode Command Line Tools (required once)

If Command Line Tools are not installed, run:

```
sudo touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress && sudo softwareupdate --install --recommended
```

Wait until installation completes before continuing.

Verify installation:

```
xcode-select -p
```

It should return:

/Library/Developer/CommandLineTools

---

## 2. Quick Start (Single Command)

Run this on a fresh macOS machine:

**Main Branch:**

```
git clone https://github.com/suleymenb/mac-setup-main.git && cd mac-setup-main && chmod +x bootstrap/bootstrap.sh verify.sh && ./bootstrap/bootstrap.sh
```

**Dev Branch:**

```
git clone -b dev https://github.com/suleymenb/mac-setup-main.git && cd mac-setup-main && chmod +x bootstrap/bootstrap.sh verify.sh && ./bootstrap/bootstrap.sh
```

This will:

1. Install Homebrew (if missing)
2. Configure PATH
3. Install pipx
4. Install ansible-core
5. Install required Ansible collections
6. Execute the Ansible playbook
7. Configure your macOS environment automatically

---

## 3. What This Setup Configures

### Core Tooling
- Homebrew
- pipx
- ansible-core
- ansible-lint

### Infrastructure
- Terraform (via the official `hashicorp/tap`)
- tflint
- terraform-docs
- Docker Desktop, docker-compose, lazydocker, dive
- kubectl, helm, k9s, kubectx, minikube

### Applications
- iTerm2
- Rectangle
- Stats
- Visual Studio Code (incl. the `code` CLI)

### VS Code Extensions
- The Digital Life theme (`xcad2k.vscode-thedigitallife`) — set as color theme
- Material Icon Theme (`PKief.material-icon-theme`) — set as file icon theme

Both are activated automatically in `settings.json`. Existing settings are
merged, not overwritten, and the previous file is kept as a `.bak`.

### CLI Tools
- eza
- dust (du-dust)
- vim (vimdiff)
- midnight commander

### Fonts
- JetBrains Mono
- Meslo LG Nerd Font

### Shell Configuration
- Oh My Zsh
- Powerlevel10k theme
- Plugins:
  - git
  - sudo
  - zsh-autosuggestions
  - zsh-syntax-highlighting
- Custom aliases:
  - `rz` - reload zshrc
  - `ls` - eza with icons and grouped directories
  - `ll` - eza long format with all files and icons
  - `k` - kubectl
- kubectl shell completion

### Not managed here
macOS system settings (dark mode, Finder preferences, Dock, etc.) are
deliberately left out — those are quicker to set by hand in System Settings
than to automate, and automating them runs into macOS permission prompts.
- Brew auto-updates

---

## 4. Project Structure

```
mac-setup-main/
├── bootstrap/
│   └── bootstrap.sh          # Initial setup script
├── roles/
│   ├── homebrew/tasks/main.yml    # Homebrew, formulae, casks, fonts
│   ├── terraform/tasks/main.yml   # HashiCorp tap, terraform, tflint
│   ├── docker/tasks/main.yml      # Docker Desktop + CLI tooling
│   ├── kubernetes/tasks/main.yml  # kubectl, helm, k9s, minikube
│   ├── vscode/tasks/main.yml      # VS Code extensions + theme settings
│   └── zsh/tasks/main.yml         # Oh My Zsh, theme, plugins, aliases
├── verify.sh                 # Post-run health check
├── playbook.yml              # Main Ansible playbook
├── inventory.ini             # Ansible inventory
├── ansible.cfg               # Ansible configuration
└── README.md                 # This file
```

---

## 4a. Verifying the Installation

`bootstrap.sh` runs this automatically at the end, but you can run it any time:

```
./verify.sh
```

It checks every item the playbook installs — brew formulae, casks, fonts,
terraform/docker/kubernetes binaries, Oh My Zsh, each `.zshrc` line, and the
macOS defaults — and prints a PASS / WARN / FAIL line per item plus a summary.
It exits non-zero if anything failed, so it works in CI too.

**Why terraform was missing:** HashiCorp moved Terraform to the Business Source
License, so Homebrew dropped it from homebrew-core. The old setup never had a
terraform task at all. It now installs from the official `hashicorp/tap`.

---

## 5. Updating Your System

To update your configuration:

```
cd ~/mac-setup-main
git pull
ansible-playbook playbook.yml
```

Or run specific roles with tags:

```
ansible-playbook playbook.yml --tags homebrew
ansible-playbook playbook.yml --tags terraform
ansible-playbook playbook.yml --tags docker
ansible-playbook playbook.yml --tags kubernetes
ansible-playbook playbook.yml --tags vscode
ansible-playbook playbook.yml --tags zsh
```

Lint the playbook before committing:

```
ansible-lint
```

---

## 6. Design Principles

- **Idempotent configuration** - Safe to run multiple times
- **Reproducible environment** - Same setup every time
- **Infrastructure-as-Code approach** - Everything is version controlled
- **Clean separation of concerns** - Organized by role (homebrew, terraform, docker, kubernetes, vscode, zsh)
- **Version-controlled system setup** - Track all changes in git

This repository serves as a reproducible macOS baseline for development environments.

---

## 7. Customization

You can customize your setup by editing:

- `roles/homebrew/tasks/main.yml` - Add/remove packages and casks
- `roles/vscode/tasks/main.yml` - Add VS Code extensions or settings
- `roles/zsh/tasks/main.yml` - Modify shell configuration and aliases
- `playbook.yml` - Include/exclude roles

---

## Troubleshooting

### Homebrew asks for confirmation during the run

This is expected. The setup runs interactively: Homebrew asks you to press
RETURN once when it installs itself, and may ask `[y/n]` before installing
formulae that pull in dependencies. Just confirm when prompted.

You are also asked for your macOS password once on a fresh machine, because
Homebrew needs `sudo` to create `/opt/homebrew`.

### `sudo: a terminal is required to read the password`

Docker Desktop's cask symlinks helper binaries into `/usr/local/bin`, which
needs root. Homebrew calls `sudo` itself, and Ansible gives it no terminal to
prompt on. There is no way around the root requirement — `--no-binaries` does
not help, Homebrew links `/usr/local/bin/kubectl` regardless.

Two ways to satisfy it:

1. **Type your password at the playbook prompt.** The play asks for it up front
   and passes it to Homebrew via `SUDO_ASKPASS`. Note that `-K` does *not* work
   here: it does not populate `ansible_become_password` for this module.
2. **Prime the sudo cache first**, then press Enter to skip the prompt:

```
sudo -v && ansible-playbook playbook.yml
```

`bootstrap.sh` does option 2 for you automatically.

---

## TO DO

- [x] brew install ansible-lint
- [x] remove rust (du-dust now comes from the brew `dust` formula, so nothing needs cargo)
- [x] install terraform (via `hashicorp/tap` — this was the broken one)
- [x] install docker
- [x] install kubernetes tooling
- [x] add a post-run verification script (`verify.sh`)
- [ ] pin tool versions for fully reproducible builds
- [ ] add a CI workflow that runs `ansible-lint` on push

---

## License

MIT
