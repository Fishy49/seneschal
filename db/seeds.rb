# ── Default user ──────────────────────────────────────────────
User.find_or_create_by!(email: "admin@seneschal.dev") do |u|
  u.password = "password"
  u.password_confirmation = "password"
  u.admin = true
end

# ── Shared skills ────────────────────────────────────────────
#
# Scaffolds an agentskills.io-conformant SKILL.md under SkillLoader.global_root
# (default <rails_root>/skills/<name>/SKILL.md), then upserts a Skill row that
# points at the file. Idempotent on both axes — the scaffolder leaves an
# existing SKILL.md alone and `find_or_initialize_by` reuses an existing row.

def seed_shared_skill(name:, description:, body:)
  result = SkillScaffolder.call(name: name, description: description, body: body)

  skill = Skill.find_or_initialize_by(name: name, project: nil)
  skill.assign_attributes(source_kind: result.source_kind, relative_path: result.relative_path)
  skill.save!
  skill.refresh_cached_metadata!
end

seed_shared_skill(
  name: "ingest_feature",
  description: "Create feature branch and draft PR from task",
  body: <<~'PROMPT'
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
)

seed_shared_skill(
  name: "plan_feature",
  description: "Explore the codebase and produce a detailed implementation plan",
  body: <<~PROMPT
    # Plan Feature Implementation

    You are working in a project repository. Produce an implementation plan
    thorough enough that a separate implementer can execute it without
    further codebase exploration.

    ## Feature

    **${task_title}**

    ${task_body}

    ## How to work

    1. Examine the project structure — understand the frameworks, conventions, and directory layout.
    2. Read files directly related to the feature area; follow imports and call sites as the feature demands.
    3. Use `grep` to find existing patterns, similar features, and relevant code.
    4. Identify the patterns from existing code you must mirror, and the project's lint/style rules.
    5. Think through edge cases implied by the feature but not explicitly stated.

    ## What the plan must cover

    - **New files** — for each, the path and a one-line reason it exists.
    - **Files to modify** — for each, the specific methods, constants, or sections being added or changed.
    - **Implementation steps** — ordered and atomic. Each step pins to a precise location (file + class/method) and includes the rationale when it isn't obvious from the change itself.
    - **Tests** — one case per acceptance criterion, with setup, the input/command, and the exact expected output text or pattern.
    - **Gotchas and constraints** — patterns to mirror, lint rules to respect, testing helpers available, and edge cases the feature implies but doesn't state.
  PROMPT
)

seed_shared_skill(
  name: "implement_feature",
  description: "Write tests and code following the plan, then push",
  body: <<~'PROMPT'
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
)

seed_shared_skill(
  name: "fix_failing_tests",
  description: "Fix CI failures based on error output",
  body: <<~'PROMPT'
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
)

Rails.logger.debug { "Seeded #{User.count} user(s), #{Skill.where(project: nil).count} shared skill(s)" }
