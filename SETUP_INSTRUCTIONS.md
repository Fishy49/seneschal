<h1 align="center">Seneschal — Setup Instructions</h1>

<p align="center">How to install Seneschal — Docker (recommended), bare-metal Linux server (Raspberry Pi, NAS, VPS, etc.), or local development. The Docker image is multi-arch and bundles every piece of tooling Seneschal shells out to; the bare-metal path is for hosts where you'd rather manage Ruby/Node/Python yourself.</p>

## Table of contents

- [Requirements](#requirements)
- [Development setup](#development-setup)
- [Production: Docker (recommended)](#production-docker-recommended)
- [Production: bare-metal Linux server](#production-bare-metal-linux-server)
  - [1. System dependencies](#1-system-dependencies)
  - [2. Install Claude CLI and GitHub CLI](#2-install-claude-cli-and-github-cli)
  - [3. Clone and install](#3-clone-and-install)
  - [4. Configure environment](#4-configure-environment)
  - [5. Database and assets](#5-database-and-assets)
  - [6. Caddy reverse proxy](#6-caddy-reverse-proxy)
  - [7. Systemd service](#7-systemd-service)
  - [8. First run](#8-first-run)
- [Optional: Claude Agent SDK runner](#optional-claude-agent-sdk-runner)
- [Updating](#updating)
- [Backups](#backups)

## Requirements

For Docker: just Docker (any 4.x or 5.x release). Multi-arch image — Intel and Apple Silicon both work.

For bare-metal:

- **Ruby 3.4+**
- **SQLite 3.8+**
- **Node.js 22+** (Tailwind CSS asset builds)
- **`git`**
- **[Claude CLI](https://docs.anthropic.com/en/docs/claude-code)** — installed and authenticated (or `ANTHROPIC_API_KEY` exported)
- **[GitHub CLI](https://cli.github.com/) (`gh`)** — installed and authenticated (or `GH_TOKEN` exported with `repo` scope)
- **Python 3.10+ + [`uv`](https://docs.astral.sh/uv/)** *(only if you want the Claude Agent SDK runner — optional, see [the section below](#optional-claude-agent-sdk-runner))*

## Development setup

```sh
git clone <repo-url> && cd seneschal
bundle install
bin/rails db:prepare
bin/rails db:seed        # scaffolds the four shared seed skills to disk
```

Optional one-time provision of the Python sidecar venv if you want to develop against the SDK runner:

```sh
bin/setup_sdk_runner
```

Start the dev server (Rails + Tailwind watcher under foreman):

```sh
bin/dev
```

Visit `http://localhost:3000`. On first visit you'll create your admin account, then be guided through an integration check (Claude CLI, GitHub CLI, optionally the SDK runner).

Additional users are invited from the **Users** page (admin only). New users receive an invite link to set their password.

## Production: Docker (recommended)

The published image at `ghcr.io/fishy49/seneschal:latest` bundles everything Seneschal needs — Ruby + Node + Python + the SDK sidecar venv + the `claude` and `gh` CLIs. Multi-arch (`linux/amd64` + `linux/arm64`), so the same tag works on a Pi, an Intel NUC, a Mac dev box, and a cloud VPS.

### Quick start — `docker run`

```sh
docker run -p 3000:3000 \
  -e SECRET_KEY_BASE=$(openssl rand -hex 64) \
  -e ANTHROPIC_API_KEY=sk-ant-... \
  -e GH_TOKEN=gh_... \
  -v $PWD/storage:/rails/storage \
  -v $PWD/repos:/rails/repos \
  -v $PWD/skills:/rails/skills \
  ghcr.io/fishy49/seneschal:latest
```

Open [http://localhost:3000](http://localhost:3000) and create the admin account. The container's entrypoint runs `db:prepare` + `db:seed` on first boot (when `storage/` is empty) and prints a banner with your next steps.

### Persistent setup — `docker compose`

For something you'd actually leave running, use the `docker-compose.yml` shipped at the repo root:

```sh
cp .env.example .env
# Fill in SECRET_KEY_BASE, ANTHROPIC_API_KEY, (optionally) GH_TOKEN.
docker compose up -d
```

Compose mounts named volumes for `storage/`, `repos/`, `skills/`, and `worktrees/` and wires the health check that hits `/up` for restart-on-failure.

### Volume layout

| Mount | Purpose | Back up? |
|---|---|---|
| `/rails/storage` | SQLite databases (primary + queue + cache + cable). | **Yes** — this is the source of truth. |
| `/rails/repos` | One git clone per Project. | Optional — re-clonable on demand. |
| `/rails/skills` | Filesystem-backed shared Skills (agentskills.io). | Optional, but cheap to keep. |
| `/rails/tmp/worktrees` | Per-run git worktrees. Ephemeral. | No. |

### Auth options

Pick **one** Claude auth path:

- **`ANTHROPIC_API_KEY`** (recommended for containers): metered usage. Works on every host, headless-friendly. If you also have a Claude Pro/Max subscription, API usage is billed separately from the flat-rate sub.
- **Claude Pro/Max OAuth — Linux hosts only**: run `claude auth login` once on the host, then bind-mount `~/.claude` read-only into the container — `-v ~/.claude:/home/rails/.claude:ro`. **macOS hosts can't do this** because `claude auth login` stores tokens in the system Keychain, not in a flat file the container can see. macOS Pro/Max users either need an API key for the container or need to run Seneschal on a Linux host.

For GitHub: set `GH_TOKEN` with `repo` scope (works everywhere), or on Linux hosts bind-mount `~/.config/gh:/home/rails/.config/gh:ro`.

### Reverse proxy

For TLS / a public domain, put Caddy or Nginx in front of the container. Example Caddyfile:

```caddyfile
seneschal.example.com {
  reverse_proxy localhost:3000
}
```

For LAN-only HTTP, omit TLS and turn off Rails' `force_ssl` by setting `RAILS_FORCE_SSL=false` in the container env.

### Building locally

If you want to build the image from a working copy (e.g. against an unmerged branch):

```sh
docker compose build      # uses docker-compose.yml's commented-out `build:` block
# or:
docker build -t seneschal:local .
```

A clean build is ~3–6 minutes on Apple Silicon; subsequent builds hit Docker's layer cache and finish in seconds for app-code-only changes.

## Production: bare-metal Linux server

For a Raspberry Pi, NAS, VPS, or any Debian/Ubuntu box where you'd rather manage Ruby / Node / Python yourself.

### 1. System dependencies

```sh
sudo apt update && sudo apt install -y \
  build-essential libsqlite3-dev libssl-dev libreadline-dev \
  libyaml-dev zlib1g-dev git curl

# Install Ruby via ruby-install + chruby (or rbenv, asdf, mise, etc.)
ruby-install ruby 3.4.9

# Install Node.js (needed for Tailwind CSS asset builds)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
```

### 2. Install Claude CLI and GitHub CLI

```sh
# Claude CLI
npm install -g @anthropic-ai/claude-code
claude auth login                              # or export ANTHROPIC_API_KEY

# GitHub CLI
# See https://github.com/cli/cli/blob/trunk/docs/install_linux.md
gh auth login                                  # or export GH_TOKEN
```

### 3. Clone and install

```sh
cd /opt
sudo mkdir seneschal && sudo chown $USER:$USER seneschal
git clone <repo-url> seneschal && cd seneschal

bundle install --without development test
```

### 4. Configure environment

Create a `.env` file or export these. At minimum you need a secret key:

```sh
export RAILS_ENV=production
export SECRET_KEY_BASE=$(bin/rails secret)
export SOLID_QUEUE_IN_PUMA=1
```

`SOLID_QUEUE_IN_PUMA=1` runs the background job processor inside the Puma web server — ideal for a single-server deployment.

If you opted for `ANTHROPIC_API_KEY` / `GH_TOKEN` rather than CLI auth, export those too.

### 5. Database and assets

```sh
bin/rails db:prepare
bin/rails db:seed          # scaffolds the four shared seed skills to disk
bin/rails assets:precompile
```

SQLite databases live in `storage/` by default. Make sure that directory is on persistent storage and backed up.

### 6. Caddy reverse proxy

Install Caddy:

```sh
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install caddy
```

Create `/etc/caddy/Caddyfile`:

```caddyfile
seneschal.run {
    reverse_proxy localhost:3000
}
```

Replace `seneschal.run` with your domain. Caddy handles TLS certificates automatically.

For LAN-only / no public domain, use HTTP:

```caddyfile
:80 {
    reverse_proxy localhost:3000
}
```

…and in `config/environments/production.rb`, comment out `config.assume_ssl` and `config.force_ssl`:

```ruby
# config.assume_ssl = true
# config.force_ssl  = true
```

Start Caddy:

```sh
sudo systemctl enable caddy
sudo systemctl start caddy
```

### 7. Systemd service

Create `/etc/systemd/system/seneschal.service`:

```ini
[Unit]
Description=Seneschal
After=network.target

[Service]
User=<your-user>
WorkingDirectory=/opt/seneschal
Environment=RAILS_ENV=production
Environment=SOLID_QUEUE_IN_PUMA=1
Environment=SECRET_KEY_BASE=<your-secret-key>
ExecStart=/bin/bash -lc 'bin/rails server -p 3000'
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

The `-lc` flag makes bash load your login profile so chruby / rbenv / asdf / mise can pick the right Ruby. Adjust `ExecStart` if your version manager works differently.

```sh
sudo systemctl daemon-reload
sudo systemctl enable seneschal
sudo systemctl start seneschal
```

### 8. First run

Visit your domain (or `http://<host-ip>`). You'll be prompted to create the admin account and walked through the integration check for Claude CLI, GitHub CLI, and — if installed — the SDK runner sidecar.

## Optional: Claude Agent SDK runner

The SDK runner is a Python sidecar that wraps the [Claude Agent SDK](https://github.com/anthropics/claude-agent-sdk-python) and buys you schema-validated structured outputs, per-call subagent definitions, MCP server configuration, and declarative policy hooks (write-confinement, etc.). You **don't** need it — the default `claude_cli` runner works for every step type — but schema-bound steps run more cleanly through the SDK because structured outputs short-circuit the prompt-engineered retry loop.

The Docker image already bundles it (built from `lib/sdk_runner/` during the image build). On bare-metal, provision the venv once with `uv`:

```sh
# Install uv if you don't have it
curl -fsSL https://astral.sh/uv/install.sh | sh

# Provision the sidecar venv
bin/setup_sdk_runner
```

`bin/setup_sdk_runner` is idempotent — re-run it any time to upgrade dependencies in place.

After the venv exists, flip the default runner on the Setup page (or in a Rails console: `Setting["default_runner"] = "claude_sdk"`). Per-step or per-workflow overrides work too — see the README's [Runners](README.md#runners) section.

## Updating

### Docker

```sh
docker compose pull && docker compose up -d
```

The entrypoint runs `db:prepare` on every boot, so migrations land automatically.

### Bare-metal

```sh
cd /opt/seneschal
git pull
bundle install --without development test
bin/rails db:migrate
bin/rails assets:precompile
sudo systemctl restart seneschal
```

After major releases, also run the one-shot post-deploy migration that fails hung runs, fixes orphan run-steps, and normalises project clones:

```sh
bin/rails seneschal:mega_update           # add DRY_RUN=1 first to preview
```

## Backups

SQLite databases live in `storage/` (or `/rails/storage/` in Docker). Back up that whole directory regularly — it's the source of truth for projects, workflows, runs, skills metadata, and run history.

For ad-hoc / off-box backups, the **Data** admin page (`/data`) downloads a full JSON export of projects, workflows, steps, skills (including SKILL.md content), step templates, and pipeline tasks. Re-importing the same file is **destructive** (wipes pipeline data before loading); user accounts and Settings are preserved.

Filesystem-backed Skills also live on disk — `<rails_root>/skills/` for shared skills, `<project>/.seneschal/skills/` for project-scoped ones, `<skill_repo_root>/<repo>/` for skill-repo-backed ones. Cloning those repos OR backing up the directories alongside `storage/` preserves your Skill library across host moves.
