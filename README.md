# mac-setup

Reproducible macOS setup with Ansible. Installs Homebrew, dev tooling, apps and
shell config, and applies a few system settings. Safe to re-run.

## Quick start

Fresh machine, one command:

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

```bash
cd ~ && git clone https://github.com/suleymenb/mac-setup-main.git && cd mac-setup-main && chmod +x bootstrap/bootstrap.sh verify.sh && ./bootstrap/bootstrap.sh
```

Clone from your home directory — `git` creates the subfolder. Cloning from
inside an existing copy nests the repo in itself; `bootstrap.sh` refuses to run
if it detects that.

`bootstrap.sh` installs Homebrew, pipx and ansible-core, runs the playbook, then
runs `verify.sh`.

**Requirement:** Xcode Command Line Tools. If `xcode-select -p` returns nothing:

```bash
xcode-select --install
```

## What it installs

|--|--|
| **CLI** | eza, dust, vim, mc, ansible-lint |
| **Infra** | terraform (`hashicorp/tap`), terraform-docs, tflint |
| **Containers** | Docker Desktop, docker-compose, lazydocker, dive |
| **Kubernetes** | kubernetes-cli, helm, k9s, kubectx, minikube |
| **Apps** | iTerm2, Rectangle, Stats, Visual Studio Code |
| **Fonts** | JetBrains Mono, Meslo LG Nerd Font |
| **Shell** | Oh My Zsh, powerlevel10k, autosuggestions, syntax-highlighting |
| **VS Code** | The Digital Life theme, Material Icon Theme (both activated) |
| **System** | Clears the Dock, dark mode, dark app icons |

Aliases: `rz` (reload zshrc), `ls`/`ll` (eza), `k` (kubectl), plus kubectl completion.

## Customising

**Edit `group_vars/all.yml`. Nothing else.** The roles install from those lists,
preflight validates them, and `verify.sh` reads the same file — so they cannot
drift apart.

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

Tags: `homebrew`, `terraform`, `docker`, `kubernetes`, `vscode`, `zsh`, `system`.
Preflight always runs.

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

**`verify.sh`** checks every installed item independently of Ansible and prints
PASS / WARN / FAIL per item. Exits non-zero on failure, so it works in CI.

## Troubleshooting

**Docker Desktop: `sudo: a terminal is required to read the password`**
Its cask needs root to symlink helpers into `/usr/local/bin`. Either type your
password at the playbook prompt, or prime sudo first:

```bash
sudo -v && ansible-playbook playbook.yml
```

`-K` does not work here — it does not populate `ansible_become_password` for
this module.

**Dark mode does not apply to open apps**
The setting is written to `AppleInterfaceStyle` and persists. Running apps pick
it up after a logout. The AppleScript alternative needs macOS Automation
permission and hangs without it, so it is off by default
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

## Layout

```
group_vars/all.yml          every package name — the only file to edit
playbook.yml                role order + final failure report
bootstrap/bootstrap.sh      first-run setup, guards against nested clones
verify.sh                   post-run health check
roles/
  preflight/                validates everything up front (not wrapped)
  homebrew/ terraform/ docker/ kubernetes/ vscode/ zsh/ system/
    tasks/main.yml          block/rescue wrapper
    tasks/tasks.yml         the actual work
  system/handlers/          restart Dock / Finder / SystemUIServer when changed
```

`system` runs last because it restarts Dock and Finder.

## Notes

- macOS system settings live in `system_defaults` in `group_vars/all.yml`.
  Find a domain and key by changing the setting in System Settings and diffing
  `defaults read` before and after.
- Terraform is not in homebrew-core (Business Source License); it comes from
  `hashicorp/tap`. tflint likewise lives in `terraform-linters/tap`.
- Restarts are Ansible handlers, so a second run restarts nothing.

## To do

- [ ] Pin tool versions
- [ ] CI on a macOS runner, running the playbook twice to prove idempotency
- [ ] Move the `brew update` out of `.zshrc` into a launchd job
- [ ] Retries on network-bound tasks

## License

MIT
