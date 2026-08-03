# mac-setup

Reproducible macOS setup with Ansible. Installs Homebrew, dev tooling, apps and
shell config, and applies a few system settings. Safe to re-run.

Tested on macOS 15 and 26, Apple Silicon and Intel. Takes roughly 15 minutes on
a fresh machine.

## Prerequisites

Xcode Command Line Tools. Check with `xcode-select -p` — it should print
`/Library/Developer/CommandLineTools`. If not:

```bash
sudo touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress && sudo softwareupdate --install --recommended
```

Wait for it to finish before continuing. Everything else is installed for you.

## Quick start

```bash
cd ~ && git clone https://github.com/suleymenb/mac-setup-main.git && cd mac-setup-main && chmod +x bootstrap/bootstrap.sh verify.sh && ./bootstrap/bootstrap.sh
```

Clone from your home directory — `git` creates the subfolder. Cloning from
inside an existing copy nests the repo in itself; `bootstrap.sh` refuses to run
if it detects that.

`bootstrap.sh` installs Homebrew, pipx and ansible-core, runs the playbook, then
runs `verify.sh`. Log out once afterwards so dark mode and scroll direction
reach every app.

## What it installs

|||
|--|--|
| **CLI** | eza, dust, vim, mc, ansible-lint |
| **Infra** | terraform (`hashicorp/tap`), terraform-docs, tflint |
| **Containers** | Docker Desktop, docker-compose, lazydocker, dive |
| **Running** | Excalidraw at http://localhost:5000 |
| **Kubernetes** | kubernetes-cli, helm, k9s, kubectx, minikube |
| **AWS** | awscli, eksctl, aws-sam-cli, aws-vault |
| **Apps** | iTerm2, Rectangle, Stats, Visual Studio Code, Sublime Text, Firefox, VLC |
| **Fonts** | JetBrains Mono, Meslo LG Nerd Font |
| **Shell** | Oh My Zsh, powerlevel10k, autosuggestions, syntax-highlighting |
| **VS Code** | The Digital Life theme, Material Icon Theme (both activated) |
| **System** | Clears the Dock, dark mode, dark app icons, natural scrolling off, Firefox as default browser, iTerm2 Nerd Font |

Aliases: `rz` (reload zshrc), `ls`/`ll` (eza), `k` (kubectl), plus kubectl completion.

## What it does not do

No dotfiles sync, no SSH or GPG keys, no App Store apps, no Time Machine or
FileVault. macOS settings are limited to what is listed above plus anything you
add to `system_defaults` yourself.

## Customising

**Edit `group_vars/all.yml`. Nothing else.** The roles install from those lists,
preflight validates them, and `verify.sh` reads the same file — so they cannot
drift apart.

Adding `jq`:

```yaml
brew_formulae:
  - eza
  - dust
  - jq        # <- add here
```

```bash
ansible-playbook playbook.yml --tags homebrew
```

Preflight checks the name exists before anything installs, and `verify.sh`
starts checking it automatically.

Adding a container:

```yaml
docker_containers:
  - name: excalidraw
    image: excalidraw/excalidraw:latest
    ports: ["5000:80"]
    url: http://localhost:5000
```

Started with `restart_policy: unless-stopped`, so it comes back after a reboot
once Docker Desktop is up. `verify.sh` checks each one is actually running.

Adding a macOS setting:

```yaml
system_defaults:
  - domain: com.apple.dock
    key: autohide
    type: bool
    value: true
```

Lists ending in `_optional` are best-effort: if Homebrew renames or moves a
package, the run logs `Skipped ...` and continues.

VS Code settings are merged into your existing `settings.json`, never
overwritten, and the original is kept as `.bak`.

## Running

```bash
ansible-playbook playbook.yml                    # everything
ansible-playbook playbook.yml --tags terraform   # one role
ansible-playbook playbook.yml --check            # dry run
./verify.sh                                      # health check
ansible-lint                                     # lint before committing
```

Tags: `homebrew`, `terraform`, `docker`, `kubernetes`, `aws`, `vscode`, `zsh`,
`system`. Preflight always runs.

AWS credentials are deliberately not managed here — they are secrets. After the
run: `aws configure sso` (recommended) or `aws configure`.

## How it fails

**Preflight** runs first and validates macOS, Xcode CLT, disk space, network,
Homebrew, sudo, and that every package name in `group_vars/all.yml` actually
resolves. Bad names are all reported at once, in seconds, before anything is
installed. If preflight fails, nothing else runs — that is deliberate.

**Every other role** is wrapped in `block`/`rescue`. A failing role is recorded
and the play continues, so one broken role never hides the state of the rest.
At the end you get a single report and a non-zero exit:

```
2 role(s) failed:
  - terraform — at task "Verify terraform is runnable"
    terraform is installed but not reachable on PATH
  - docker — at task "Fail loudly if Docker Desktop is still missing"

Re-run just the failed ones, for example:
  ansible-playbook playbook.yml --tags terraform,docker
```

**`verify.sh`** checks everything independently of Ansible:

```
mac-setup verification  —  2026-08-01 15:32

— Terraform —
  ✔ hashicorp/tap tapped
  ✔ terraform (brew)                   terraform 1.15.8
  ✔ terraform binary                   Terraform v1.15.8
  ! tflint                             optional — brew install terraform-linters/tap/tflint

— Kubernetes —
  ✔ kubernetes-cli (kubectl)           kubernetes-cli 1.36.2
  ✔ helm                               helm 3.19.1

— System —
  ✔ Dock has no pinned apps
  ✔ Dark mode enabled
  ✔ Natural scrolling off

────────────────────────────────────────
  passed: 61   warnings: 3   failed: 0
```

Exits non-zero on failure, so it works in CI too.

## Troubleshooting

**Docker Desktop: `sudo: a terminal is required to read the password`**
Its cask needs root to symlink helpers into `/usr/local/bin`. Either type your
password at the playbook prompt, or prime sudo first:

```bash
sudo -v && ansible-playbook playbook.yml
```

`-K` does not work here — it does not populate `ansible_become_password` for
this module.

**Powerlevel10k shows boxes or question marks instead of icons**
Installing the font cask only puts files in `~/Library/Fonts` — the terminal
still has to select one. The system role sets iTerm2's font to
`MesloLGSNerdFont-Regular`, but **only while iTerm2 is closed**: iTerm2 rewrites
its entire preferences file when it quits and would throw the change away.

```bash
# quit iTerm2 first, then from Terminal.app:
ansible-playbook playbook.yml --tags system
```

Font in `system_iterm_font`. Alternatively `p10k configure` walks you through it.

**Firefox did not become the default browser**
macOS does not allow changing this silently — it shows a confirmation dialog you
have to click. The playbook asks, you confirm. Check with `defaultbrowser`, or
set it in System Settings › Desktop & Dock › Default web browser.

**Dark mode or scroll direction did not change**
Both are written as preferences and persist, but running apps only pick them up
after a logout. For dark mode the AppleScript alternative applies instantly, but
needs macOS Automation permission and hangs without it, so it is off by default
(`system_dark_mode_live_apply`).

**`terraform: command not found` after a successful run**
The binary is installed but not linked or not on PATH:

```bash
brew link --overwrite hashicorp/tap/terraform
eval "$(/opt/homebrew/bin/brew shellenv)"
```

**Homebrew asks for confirmation**
Expected. Confirm when prompted; you are also asked for your macOS password once
because Homebrew needs sudo to create `/opt/homebrew`.

## Undoing things

```bash
brew uninstall <formula>              # or: brew uninstall --cask <cask>
brew list --formula                   # what is installed
```

Everything this playbook wrote to `~/.zshrc` sits between markers, so it is easy
to find and delete:

```
# BEGIN ANSIBLE_ALIASES ... # END ANSIBLE_ALIASES
# BEGIN ANSIBLE_OMZ_SETTINGS, ANSIBLE_KUBECTL, ANSIBLE_BREW_AUToupdates
```

VS Code settings: restore the `settings.json.*.bak` next to the original.
macOS settings: `defaults delete -g <key>`, for example
`defaults delete -g com.apple.swipescrolldirection`.

Remove a package permanently by deleting it from `group_vars/all.yml`, then
moving it to the matching `_absent` list so future runs uninstall it too.

## Layout

```
group_vars/all.yml          every package name — the only file to edit
playbook.yml                role order + final failure report
bootstrap/bootstrap.sh      first-run setup, guards against nested clones
verify.sh                   post-run health check
roles/
  preflight/                validates everything up front (not wrapped)
  homebrew/ terraform/ docker/ kubernetes/ aws/ vscode/ zsh/ system/
    tasks/main.yml          block/rescue wrapper
    tasks/tasks.yml         the actual work
  system/handlers/          restart Dock / Finder / SystemUIServer when changed
```

`system` runs last because it restarts Dock and Finder.

## Notes

- Find the domain and key of any macOS setting by changing it in System Settings
  and diffing `defaults read` before and after.
- Terraform is not in homebrew-core (Business Source License); it comes from
  `hashicorp/tap`. tflint likewise lives in `terraform-linters/tap`.
- Restarts are Ansible handlers, so a second run restarts nothing.
- `AppleIconAppearanceTheme` (dark app icons) needs macOS 26 or later; on older
  versions it is simply ignored.

## To do

- [ ] Pin tool versions
- [ ] CI on a macOS runner, running the playbook twice to prove idempotency
- [ ] Move the `brew update` out of `.zshrc` into a launchd job
- [ ] Retries on network-bound tasks

## License

MIT
