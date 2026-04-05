# ── Default user ──────────────────────────────────────────────
User.find_or_create_by!(email: "admin@seneschal.dev") do |u|
  u.password = "password"
  u.password_confirmation = "password"
end

# ── Shared skills ────────────────────────────────────────────

ingest_skill = Skill.find_or_create_by!(name: "ingest_feature", project: nil) do |s|
  s.description = "Create feature branch and draft PR from task"
  s.body = <<~'PROMPT'
    # Ingest Feature

    You are working in a project repository.

    ## Task

    Create a feature branch and draft PR for: ${task_title}

    ## Description

    ${task_body}

    ## Instructions

    1. Run `git checkout main && git pull`
    2. Derive a branch name from the task title: lowercase, replace spaces with hyphens, prefix with `feature/`
    3. Create and push the branch: `git checkout -b <branch> && git push -u origin <branch>`
    4. Create an empty commit: `git commit --allow-empty -m "chore: initialize <branch>"`
    5. Push: `git push`
    6. Create a draft PR:
       ```
       gh pr create --draft \
         --title "${task_title}" \
         --body "## Description\n\n${task_body}\n\nKind: ${task_kind}"
       ```
    7. Parse the PR number from the URL printed by `gh pr create`

    ## Output

    Print exactly one summary line:
    ```
    PR #<number> created on branch feature/<branch-name>
    ```
  PROMPT
end

plan_skill = Skill.find_or_create_by!(name: "plan_feature", project: nil) do |s|
  s.description = "Explore codebase and write a detailed implementation plan"
  s.body = <<~'PROMPT'
    # Plan Feature Implementation

    You are working in a project repository.

    ## Task

    Produce a detailed implementation plan for the following feature. The plan must be thorough enough that a separate agent can execute it without further codebase exploration.

    ## Feature

    **${task_title}**

    ${task_body}

    ## Exploration

    1. Examine the project structure — understand the frameworks, conventions, and directory layout.
    2. Read files directly related to the feature area.
    3. Use grep to find existing patterns, similar features, and relevant code.

    ## Plan Format

    Output the plan with exactly these five sections:

    ### 1. Files to create
    Each new file: full path + one-line purpose.

    ### 2. Files to modify
    Each changed file: full path + specific changes (name the methods/constants being added or changed).

    ### 3. Implementation steps
    Ordered, atomic steps. For each: what to write/change, exact location (file + class/method), and why if non-obvious.

    ### 4. Test plan
    For each acceptance criterion: test name, setup, input, and expected output.

    ### 5. Gotchas and constraints
    - Patterns from existing code that must be followed
    - Linting/style rules observed in the project
    - Testing helpers and conventions
    - Edge cases implied by the feature but not stated

    ## Output

    Output ONLY the implementation plan. Do not include any preamble, commentary, or summary lines.
  PROMPT
end

implement_skill = Skill.find_or_create_by!(name: "implement_feature", project: nil) do |s|
  s.description = "Write tests and code following the plan, then push"
  s.body = <<~'PROMPT'
    # Implement Feature

    You are working in a project repository.

    **IMPORTANT: Do NOT run tests, linters, or any validation commands locally.** CI will handle all validation after you push. Focus only on writing correct code and tests.

    ## Task

    Implement the following feature by writing tests first, then code.

    **${task_title}**

    ## Implementation Plan

    ${implementation_plan}

    ## Phase 1: Write Tests

    1. Create test file(s) as described in the plan's Test Plan section.
    2. Follow existing test patterns and conventions in the project.

    ## Phase 2: Implement

    Work through the Implementation Steps from the plan in order.

    ## Phase 3: Commit and Push

    1. Stage all changes
    2. `git commit -m "feat: ${task_title}"`
    3. `git push`

    ## Output

    Print: `Implementation complete for PR #${pr_number}`
  PROMPT
end

fix_skill = Skill.find_or_create_by!(name: "fix_failing_tests", project: nil) do |s|
  s.description = "Fix CI failures based on error output"
  s.body = <<~'PROMPT'
    # Fix Failing Tests

    You are working in a project repository.

    ## Task

    CI checks have failed. Fix the failing tests and/or code issues described below.

    ## Failure Details

    ${ci_failure_details}

    ## Instructions

    1. Read the failure output carefully — identify which tests failed and why.
    2. Read the relevant source and test files.
    3. Fix the root cause. Do not just make the test pass — fix the underlying issue.
    4. If the failure is a linting/style issue, fix it to match project conventions.
    5. Stage, commit, and push:
       ```
       git add -A
       git commit -m "fix: address CI failures"
       git push
       ```

    **IMPORTANT: Do NOT run tests locally.** CI will re-validate after you push.

    ## Output

    Print: `Fixes pushed for PR #${pr_number}`
  PROMPT
end

puts "Seeded #{User.count} user(s), #{Skill.where(project: nil).count} shared skill(s)"
