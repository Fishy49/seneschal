<p align="center">
  <img src="app/assets/images/logo.png" width="80" alt="Seneschal" />
</p>

<h1 align="center">Seneschal</h1>

<p align="center">An AI pipeline orchestrator for software projects. Define workflows that use Claude to plan, implement, and validate features, then watch them run.</p>

## What it does

Seneschal connects your Git repositories to multi-step AI workflows. A typical pipeline might:

1. Create a feature branch and draft PR
2. Explore the codebase and write an implementation plan
3. Implement the feature (tests first, then code)
4. Monitor CI checks and automatically retry on failure

Each step can be a **skill** (a Claude CLI prompt), a **shell script**, a **command**, or a **CI check** monitor. Steps pass context to each other through captured outputs and template variables. Failed CI checks can inject fix-up steps into the running pipeline and re-check automatically.

Streaming output from Claude skills is captured in real time and stored for historical review.

## Requirements

- Ruby 3.4+
- SQLite 3.8+
- Node.js (for Tailwind CSS builds)
- [Claude CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
- [GitHub CLI](https://cli.github.com/) (`gh`) installed and authenticated

## Development setup

```sh
git clone <repo-url> && cd seneschal
bundle install
bin/rails db:prepare
bin/rails db:seed        # creates shared skills
```

Start the dev server (runs Rails + Tailwind watcher):

```sh
bin/dev
```

Visit `http://localhost:3000`. On first visit you'll create your admin account, then be guided through an integration check to verify that `claude` and `gh` are available on the host.

Additional users can be created from the **Users** page (admin only). New users receive an invite link to set their password.

## Production setup (Raspberry Pi)

This guide covers running Seneschal on a Raspberry Pi (or any Debian/Ubuntu server) with Caddy for automatic HTTPS.

### 1. System dependencies

```sh
sudo apt update && sudo apt install -y \
  build-essential libsqlite3-dev libssl-dev libreadline-dev \
  libyaml-dev zlib1g-dev git curl

# Install Ruby via ruby-install + chruby (or rbenv, asdf, etc.)
# See https://github.com/postmodern/ruby-install
ruby-install ruby 3.4.9

# Install Node.js (needed for Tailwind CSS asset builds)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
```

### 2. Install Claude CLI and GitHub CLI

```sh
# Claude CLI
npm install -g @anthropic-ai/claude-code
claude auth login

# GitHub CLI
# See https://github.com/cli/cli/blob/trunk/docs/install_linux.md
gh auth login
```

### 3. Clone and install

```sh
cd /opt
sudo mkdir seneschal && sudo chown $USER:$USER seneschal
git clone <repo-url> seneschal && cd seneschal

bundle install --without development test
```

### 4. Configure environment

Create a `.env` file or export these variables. At minimum you need a secret key:

```sh
export RAILS_ENV=production
export SECRET_KEY_BASE=$(bin/rails secret)
export SOLID_QUEUE_IN_PUMA=1
```

`SOLID_QUEUE_IN_PUMA=1` runs the background job processor inside the Puma web server, which is ideal for a single-server deployment like a Pi.

### 5. Database and assets

```sh
bin/rails db:prepare
bin/rails db:seed          # loads shared skills
bin/rails assets:precompile
```

SQLite databases are created in `storage/` by default. Make sure this directory is on persistent storage and backed up.

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

If you're running on a local network without a public domain, use HTTP only:

```caddyfile
:80 {
    reverse_proxy localhost:3000
}
```

And in `config/environments/production.rb`, comment out or disable `config.assume_ssl` and `config.force_ssl`:

```ruby
# config.assume_ssl = true
# config.force_ssl = true
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

If you use chruby, rbenv, or asdf, the `-lc` flag ensures your shell profile loads so the correct Ruby is available. Adjust the `ExecStart` if your setup differs.

```sh
sudo systemctl daemon-reload
sudo systemctl enable seneschal
sudo systemctl start seneschal
```

### 8. First run

Visit your domain (or `http://<pi-ip>`). You'll be prompted to create your admin account, then guided through the integration check for Claude CLI and GitHub CLI.

### Updating

```sh
cd /opt/seneschal
git pull
bundle install --without development test
bin/rails db:migrate
bin/rails assets:precompile
sudo systemctl restart seneschal
```

### Backups

SQLite databases live in `storage/`. Back up this directory regularly. You can also use the built-in **Data** export (admin sidebar) to download all projects, workflows, skills, and tasks as a JSON file.

## Concepts

| Concept | Description |
|---------|-------------|
| **Project** | A Git repository. Cloned locally for Claude to work in. |
| **Workflow** | An ordered sequence of steps belonging to a project. |
| **Step** | A single unit of work: skill, script, command, or ci_check. |
| **Skill** | A reusable Claude CLI prompt template. Can be shared across projects or scoped to one. |
| **Task** | A feature/bug/chore that gets fed into a workflow as context. |
| **Run** | One execution of a workflow for a given task. Tracks status of each step. |
| **Step Template** | A saved step configuration for quick reuse across workflows. |

### Step types

- **skill** - Sends a prompt to Claude CLI. Supports `--output-format stream-json` for real-time streaming. Can capture output into named variables for downstream steps.
- **script** - Runs a shell script with environment variables from previous step outputs.
- **command** - Runs a single shell command.
- **ci_check** - Polls GitHub PR checks. On failure, can inject steps (like a fix skill) back into the running pipeline and re-validate.

### Failure injection

CI check steps can be configured with `on_failure_inject` to automatically insert repair steps when checks fail. For example, a CI check can inject a "fix failing tests" skill followed by another CI check, creating a retry loop that runs until tests pass or the injection limit is reached.

Steps can be marked as **inject only**, meaning they do not run in the normal workflow sequence but are available as injection targets.

## Stack

- Rails 8.1 with SQLite
- Solid Queue for background jobs
- Hotwire (Turbo + Stimulus) for real-time UI
- Tailwind CSS v4
- Propshaft asset pipeline
