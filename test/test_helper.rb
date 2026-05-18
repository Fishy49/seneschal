ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Filesystem-backed Skill fixtures need real SKILL.md files on disk at the
# paths the AR `skills` fixture rows resolve to. The shared fixture
# (`shared_skill`) points at <test/fixtures/files/skills/ingest_feature/>
# via a Setting override; the project-scoped fixture (`project_skill`)
# resolves to <tmp/test_repos/seneschal/.seneschal/skills/deploy_check/>,
# so we materialize that file at load time. Idempotent — tests that
# mutate either are responsible for their own cleanup.
module FilesystemSkillFixtures
  FIXTURE_SKILLS_ROOT = Rails.root.join("test/fixtures/files/skills").to_s.freeze
  PROJECT_SKILL_TARGET = Rails.root.join(
    "tmp/test_repos/seneschal/.seneschal/skills/deploy_check"
  ).freeze

  module_function

  def materialize!
    FileUtils.mkdir_p(PROJECT_SKILL_TARGET)
    target = PROJECT_SKILL_TARGET.join("SKILL.md")
    source = File.join(FIXTURE_SKILLS_ROOT, "deploy_check", "SKILL.md")
    FileUtils.cp(source, target) unless File.exist?(target)
  end
end

FilesystemSkillFixtures.materialize!

module ActiveSupport
  class TestCase
    fixtures :all
    parallelize(workers: :number_of_processors)

    # Point SkillLoader.global_roots at the test fixture tree so the shared
    # `ingest_feature` skill fixture resolves to a real on-disk SKILL.md.
    # Tests that want a different global root (e.g. SkillsControllerTest's
    # tmpdir) override this in their own setup block.
    setup do
      Setting["skills_global_roots"] = FilesystemSkillFixtures::FIXTURE_SKILLS_ROOT
    end
  end
end

# Sign-in helpers for integration tests
ActionDispatch::IntegrationTest.class_eval do
  private

  def sign_in(user, password: "password")
    post login_path, params: { email: user.email, password: password }
    follow_redirect!
  end

  def sign_out
    delete logout_path
    follow_redirect!
  end
end
