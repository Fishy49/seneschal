# Turns a user's stored Connections into the environment overlay their runs
# execute under.
#
# The returned hash is merged over the parent process environment by Open3 at
# the spawn seam, so an EMPTY overlay leaves today's host-session behaviour
# (`claude setup-token` / `gh auth login` on the server) exactly as it was.
# That is the whole compatibility story: nothing is replaced, only overridden
# when a user has explicitly connected their own identity.
#
# Variable names follow the CLIs' own documented precedence:
#   claude : ANTHROPIC_API_KEY > CLAUDE_CODE_OAUTH_TOKEN > stored login
#   gh     : GH_TOKEN > GITHUB_TOKEN > stored login
class CredentialEnv
  # When a user has stored both Claude credential kinds we send only the API
  # key, matching the CLI's own precedence, so the two cannot disagree about
  # which identity is in use.
  def self.for(user)
    return {} if user.blank?

    credentials = user.user_credentials.index_by(&:kind)
    env = {}

    if (github = credentials["github_token"])
      env["GH_TOKEN"] = github.value
      env.merge!(git_identity(user))
    end

    if (api_key = credentials["anthropic_api_key"])
      env["ANTHROPIC_API_KEY"] = api_key.value
    elsif (oauth = credentials["claude_oauth_token"])
      env["CLAUDE_CODE_OAUTH_TOKEN"] = oauth.value
    end

    env
  end

  # Commits made with someone's GitHub token should carry their name, not the
  # server's git config.
  def self.git_identity(user)
    name = user.email.to_s.split("@").first.presence || user.email.to_s
    {
      "GIT_AUTHOR_NAME" => name,
      "GIT_AUTHOR_EMAIL" => user.email.to_s,
      "GIT_COMMITTER_NAME" => name,
      "GIT_COMMITTER_EMAIL" => user.email.to_s
    }
  end
  private_class_method :git_identity
end
