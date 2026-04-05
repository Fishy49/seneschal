require "application_system_test_case"

class SkillsTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:admin)
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

  test "create shared skill" do
    visit new_skill_path
    fill_in "Name", with: "new_test_skill"
    page.execute_script("document.querySelector('input[name=\"skill[body]\"]').value = 'Do the thing'")
    click_on "Create Skill"

    assert_text "new_test_skill"
  end

  test "edit skill" do
    visit edit_skill_path(skills(:shared_skill))
    fill_in "Name", with: "renamed_skill"
    click_on "Update Skill"

    assert_text "renamed_skill"
  end

  test "delete skill" do
    visit skill_path(skills(:project_skill))
    accept_confirm { click_on "Delete" }

    assert_current_path skills_path
    assert_no_text "deploy_check"
  end
end
