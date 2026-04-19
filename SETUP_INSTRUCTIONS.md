<h1 align="center">Seneschal — Setup Instructions</h1>

<p align="center">How to install and run Seneschal locally for development, or in production on a Raspberry Pi (or any Debian/Ubuntu server) behind Caddy.</p>

## Table of contents

- [Requirements](#requirements)
- [Development setup](#development-setup)
- [Production setup (Raspberry Pi)](#production-setup-raspberry-pi)
  - [1. System dependencies](#1-system-dependencies)
  - [2. Install Claude CLI and GitHub CLI](#2-install-claude-cli-and-github-cli)
  - [3. Clone and install](#3-clone-and-install)
  - [4. Configure environment](#4-configure-environment)
  - [5. Database and assets](#5-database-and-assets)
  - [6. Caddy reverse proxy](#6-caddy-reverse-proxy)
  - [7. Systemd service](#7-systemd-service)
  - [8. First run](#8-first-run)
  - [Updating](#updating)
  - [Backups](#backups)

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
