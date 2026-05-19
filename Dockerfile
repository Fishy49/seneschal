# syntax=docker/dockerfile:1
# check=error=true
#
# Production-ready image for Seneschal — bundles the full agent toolchain
# (Ruby + Node + Python venv + claude CLI + gh CLI + git) so a `docker run`
# is genuinely "afternoon install" friendly. The image is multi-arch
# (linux/amd64 + linux/arm64) and gets published to GHCR by .github/workflows/
# docker.yml on every push to main + tagged release.
#
# Usage:
#   docker run -p 3000:3000 \
#     -e SECRET_KEY_BASE=$(openssl rand -hex 64) \
#     -e ANTHROPIC_API_KEY=sk-ant-... \
#     -e GH_TOKEN=gh_... \
#     -v $PWD/storage:/rails/storage \
#     -v $PWD/repos:/rails/repos \
#     -v $PWD/skills:/rails/skills \
#     ghcr.io/fishy49/seneschal:latest
#
# See README.md "Docker quick start" for compose, persistent auth, and
# Claude Pro / OAuth setup.

ARG RUBY_VERSION=3.4.9
ARG NODE_VERSION=22
ARG PYTHON_VERSION=3.12
ARG CLAUDE_CODE_VERSION=2.1.142

# ============================================================
# Stage 1: base — runtime OS deps shared by build and final stages
# ============================================================
FROM docker.io/library/ruby:${RUBY_VERSION}-slim AS base

ARG NODE_VERSION
ARG PYTHON_VERSION
ARG CLAUDE_CODE_VERSION

WORKDIR /rails

# Runtime dependencies:
#   - git: every project lives in a worktree; gh + claude shell out to git
#   - curl, ca-certificates: needed by Node install + downstream tooling
#   - sqlite3 + libjemalloc2: app's database driver + memory allocator
#   - python3: hosts the Claude Agent SDK sidecar (lib/sdk_runner/.venv)
#   - gh: GitHub CLI, used by the `pr` step type and seeded workflows
#   - uv: bootstraps the sidecar venv (Debian slim's `python3 -m venv` ships
#     without working ensurepip, so we use uv — which the setup script
#     already prefers when present)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      ca-certificates curl git sqlite3 libjemalloc2 \
      python3 \
      gnupg lsb-release && \
    # Node.js for Tailwind asset builds + claude CLI (npm package).
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash - && \
    apt-get install --no-install-recommends -y nodejs && \
    # GitHub CLI from the official Debian repo.
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
      dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y gh && \
    # claude CLI (Anthropic's agent runtime).
    npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" && \
    # uv (Astral) — static binary, no python deps. Installs to /usr/local/bin.
    curl -fsSL https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh && \
    # libjemalloc preload — same as stock Rails Dockerfile.
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives ~/.npm

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    SOLID_QUEUE_IN_PUMA="1"

# ============================================================
# Stage 2: build — compile gems, assets, and the Python sidecar venv
# ============================================================
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Bundler first so dep changes don't bust the app-code cache layer.
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # `-j 1` works around a bootsnap+QEMU bug on cross-arch builds.
    bundle exec bootsnap precompile -j 1 --gemfile

COPY . .

# Build the Python sidecar venv into the image so the SDK runner works
# out of the box. Uses bin/setup_sdk_runner, which is already idempotent.
RUN ./bin/setup_sdk_runner

RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Asset precompile needs a dummy secret only at build time; the real one
# comes from SECRET_KEY_BASE at runtime.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# ============================================================
# Stage 3: runtime — minimal image with only the artifacts we need
# ============================================================
FROM base

# Run as a non-root user — but uid:gid 1000:1000 line up with most host
# linux users, which keeps bind-mounted volumes writable without chmod gymnastics.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

# Bring over gems + app code + the prebuilt sidecar venv.
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Pre-create the writable mount targets so an empty named volume doesn't
# start out owned by root.
RUN install -d -o 1000 -g 1000 \
      /rails/storage /rails/repos /rails/skills /rails/tmp /rails/tmp/worktrees /rails/log

USER 1000:1000

# Entrypoint runs db:prepare on first boot and surfaces a clear next-steps
# banner so a fresh user knows what to do.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]
