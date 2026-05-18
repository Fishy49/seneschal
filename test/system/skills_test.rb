require "application_system_test_case"

class SkillsTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:admin)
    @tmp_global_root = Dir.mktmpdir
    Setting["skills_global_roots"] = @tmp_global_root
  end

  teardown do
    FileUtils.remove_entry(@tmp_global_root) if @tmp_global_root && File.directory?(@tmp_global_root)
    Setting.where(key: "skills_global_roots").delete_all
  end

  test "list skills" do
    visit skills_path
    assert_text "ingest_feature"
    assert_text "deploy_check"
  end

  test "view skill details" do
    visit skill_path(skills(:shared_skill))
    assert_text "ingest_feature"
  end

  test "creating a shared skill writes SKILL.md to the global root on disk" do
    visit new_skill_path
    fill_in "Name", with: "new-test-skill"
    fill_in "Description", with: "Test skill created via the form"

    # The body field is rendered as a hidden input fed by a code-editor
    # Stimulus controller; setting the hidden value directly is the same
    # trick the older test used and survives codejar's lifecycle.
    page.execute_script(
      "document.querySelector('input[name=\"skill[body]\"]').value = 'Do the thing.\\n'"
    )
    click_on "Create Skill"

    # Wait for the show page to settle before touching the filesystem so the
    # server-side write is guaranteed to have completed.
    assert_text "Skill scaffolded"

    expected_dir = File.join(@tmp_global_root, "new-test-skill")
    expected_skill_md = File.join(expected_dir, "SKILL.md")

    assert File.directory?(expected_dir), "Expected directory at #{expected_dir}"
    assert File.file?(expected_skill_md), "Expected SKILL.md at #{expected_skill_md}"

    contents = File.read(expected_skill_md)
    assert_match(/^name:\s*new-test-skill\s*$/, contents)
    assert_match(/^description:\s*Test skill created via the form\s*$/, contents)
    assert_match("Do the thing.", contents)

    # Show page surfaces the on-disk path + the synced description so the
    # author knows where to edit. The page rendering is the user-facing proof
    # of the DB row's source_kind / relative_path / description fields.
    assert_text expected_dir
    assert_text "new-test-skill"
    assert_text "Test skill created via the form"
  end

  test "creating a project skill writes SKILL.md under <project>/.seneschal/skills/<name>/" do
    project = projects(:seneschal)
    skills_subtree = File.join(project.local_path, ".seneschal")

    # The fixture project's local_path doesn't necessarily exist on disk; ensure
    # it does so the scaffolder has a parent to mkdir under, and clean up.
    FileUtils.mkdir_p(project.local_path)

    begin
      visit new_skill_path
      fill_in "Name", with: "proj-skill"
      fill_in "Description", with: "Project-only skill"
      select "Project: #{project.name}", from: "Scope"
      page.execute_script(
        "document.querySelector('input[name=\"skill[body]\"]').value = 'Body content.\\n'"
      )
      click_on "Create Skill"

      # Wait for the show page so we know the server-side write + redirect
      # are complete before we touch the filesystem.
      assert_text "Skill scaffolded"

      expected_skill_md = File.join(project.local_path, ".seneschal", "skills", "proj-skill", "SKILL.md")
      assert File.file?(expected_skill_md), "Expected SKILL.md at #{expected_skill_md}"
      assert_match("Body content.", File.read(expected_skill_md))

      # The show page banner asserts the DB-level state — source_kind and
      # relative_path resolve to that exact on-disk path. Avoid querying the
      # AR model directly: in transactional system tests the row a Puma-thread
      # request created may not always be visible to the test thread without
      # extra connection sharing.
      assert_text File.join(project.local_path, ".seneschal", "skills", "proj-skill")
    ensure
      FileUtils.rm_rf(skills_subtree)
    end
  end

  test "creating a skill with an invalid name surfaces the validation error and writes nothing" do
    visit new_skill_path
    fill_in "Name", with: "Bad Name With Spaces"
    fill_in "Description", with: "x"
    click_on "Create Skill"

    assert_text(/kebab-case/i)
    # No file should have been written to the tmp global root.
    assert_empty Dir.glob(File.join(@tmp_global_root, "*"))
  end

  test "creating a skill with a name that already exists on disk surfaces a conflict error" do
    FileUtils.mkdir_p(File.join(@tmp_global_root, "already-here"))
    File.write(
      File.join(@tmp_global_root, "already-here", "SKILL.md"),
      "---\nname: already-here\ndescription: pre-existing\n---\n\nbody\n"
    )

    visit new_skill_path
    fill_in "Name", with: "already-here"
    fill_in "Description", with: "Conflicting"
    click_on "Create Skill"

    assert_text(/already exists/i)
    assert_nil Skill.find_by(name: "already-here")
  end

  test "show page renders frontmatter, scripts and references that exist alongside SKILL.md" do
    skill_dir = File.join(@tmp_global_root, "rich-skill")
    FileUtils.mkdir_p(File.join(skill_dir, "scripts"))
    FileUtils.mkdir_p(File.join(skill_dir, "references"))
    File.write(File.join(skill_dir, "SKILL.md"), <<~MD)
      ---
      name: rich-skill
      description: Has helper files
      allowed-tools: Read, Grep
      ---

      # Rich Skill body
    MD
    File.write(File.join(skill_dir, "scripts", "do_thing.sh"), "#!/bin/bash\necho hello\n")
    File.write(File.join(skill_dir, "references", "patterns.md"), "## Pattern\n\nExample.\n")
    skill = Skill.create!(name: "rich-skill", source_kind: "global", relative_path: "rich-skill")
    skill.refresh_cached_metadata!

    visit skill_path(skill)
    assert_text "rich-skill"
    assert_text skill_dir
    assert_text "Frontmatter"
    assert_text "allowed-tools"
    assert_text "Read, Grep"
    assert_text "scripts/"
    assert_text "do_thing.sh"
    assert_text "references/"
    assert_text "patterns.md"
  end

  test "show page auto-syncs cached frontmatter when SKILL.md changes on disk" do
    skill_dir = File.join(@tmp_global_root, "evolving")
    FileUtils.mkdir_p(skill_dir)
    File.write(File.join(skill_dir, "SKILL.md"), <<~MD)
      ---
      name: evolving
      description: Original description
      ---

      body
    MD
    skill = Skill.create!(name: "evolving", source_kind: "global", relative_path: "evolving")
    skill.refresh_cached_metadata!

    File.write(File.join(skill_dir, "SKILL.md"), <<~MD)
      ---
      name: evolving
      description: Updated description
      ---

      new body
    MD

    visit skill_path(skill)
    # The show page's auto-refresh re-reads SKILL.md when the on-disk hash
    # has drifted. Confirming the new description renders is sufficient
    # proof the cache was synced — querying AR from the test thread would
    # cross the system-test transactional isolation boundary.
    assert_text "Updated description"
  end

  test "edit form lets the user change scope without touching name or body" do
    skill = skills(:shared_skill)
    visit edit_skill_path(skill)

    # Edit form deliberately omits Name (rename on disk) and Body (lives in
    # SKILL.md) — just verify scope is mutable.
    select "Group: Frontend", from: "Scope"
    click_on "Update Skill"

    # Wait for redirect to show. The show page renders the group name in the
    # header so we don't need to query AR from the test thread (system tests
    # run the Puma server on a thread whose new rows aren't always visible
    # from the test thread under transactional isolation).
    assert_text "Skill updated"
    assert_text "Group: Frontend"
  end

  test "delete skill" do
    visit skill_path(skills(:project_skill))
    accept_confirm { click_on "Delete" }

    assert_current_path skills_path
    assert_no_text "deploy_check"
  end
end
