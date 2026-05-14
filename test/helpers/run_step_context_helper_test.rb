require "test_helper"
require "tmpdir"
require "fileutils"

class RunStepContextHelperTest < ActionView::TestCase
  include RunStepContextHelper

  setup do
    @project = projects(:seneschal)
    @tmpdir = Dir.mktmpdir("seneschal-claude-md-")
    @project.update!(local_path: @tmpdir, repo_status: "ready")
  end

  teardown do
    FileUtils.rm_rf(@tmpdir) if @tmpdir
  end

  # Regression: `File.read(path, length)` returns an ASCII-8BIT-encoded
  # string. If CLAUDE.md contains any non-ASCII byte, interpolating that
  # binary string into a UTF-8 ERB template throws Encoding::CompatibilityError
  # at render time — and run show pages started crashing as soon as a managed
  # project's CLAUDE.md picked up an em-dash or smart quote.
  test "claude_md_section returns UTF-8 content even when CLAUDE.md has non-ASCII bytes" do
    File.write(
      File.join(@tmpdir, "CLAUDE.md"),
      "# Heading — with em-dash and smart quotes “like this”.\n\n#{"x" * 100}"
    )

    section = send(:claude_md_section, @project)

    assert_equal Encoding::UTF_8, section[:content].encoding
    assert section[:content].valid_encoding?
    assert_includes section[:content], "em-dash"
  end

  test "claude_md_section truncates oversize CLAUDE.md without breaking encoding" do
    # Build a file where the byte-truncation boundary would land mid-multibyte
    # if we weren't scrubbing. Each em-dash is 3 bytes, so pad to right before
    # the cap and then add em-dashes.
    pad = "a" * (RunStepContextHelper::CLAUDE_MD_MAX_BYTES - 1)
    File.write(File.join(@tmpdir, "CLAUDE.md"), pad + ("—" * 100))

    section = send(:claude_md_section, @project)

    assert_equal Encoding::UTF_8, section[:content].encoding
    assert section[:content].valid_encoding?, "scrub should have replaced any incomplete multibyte tail"
    assert_includes section[:subtitle], "truncated"
  end

  test "claude_md_section returns blank message when CLAUDE.md is missing" do
    section = send(:claude_md_section, @project)
    assert_nil section[:content]
    assert_match(/no claude\.md/i, section[:blank])
  end
end
