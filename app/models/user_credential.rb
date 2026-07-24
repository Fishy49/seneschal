# A single stored secret belonging to one user, used to run their pipeline
# steps under their own identity instead of the host's shared CLI sessions.
#
# The plaintext is only ever read at the process-spawn seam
# (`CredentialEnv.for` -> `StepExecutor#env_vars`). Nothing renders it.
class UserCredential < ApplicationRecord
  belongs_to :user

  KINDS = ["github_token", "anthropic_api_key", "claude_oauth_token"].freeze

  KIND_LABELS = {
    "github_token" => "GitHub token",
    "anthropic_api_key" => "Anthropic API key",
    "claude_oauth_token" => "Claude OAuth token"
  }.freeze

  encrypts :value

  validates :kind, presence: true, inclusion: { in: KINDS },
                   uniqueness: { scope: :user_id }
  validates :value, presence: true

  normalizes :value, with: ->(v) { v.to_s.strip }

  def label = KIND_LABELS.fetch(kind, kind)

  # A shape hint for the account page. Deliberately never the value, and
  # never a prefix long enough to be useful to anyone reading over a
  # shoulder or scraping a screenshot.
  def masked
    "#{"•" * 12} (#{value.to_s.length} characters)"
  end
end
