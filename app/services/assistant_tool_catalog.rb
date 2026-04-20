class AssistantToolCatalog
  BASE_ENV = "ASSISTANT_API_BASE".freeze
  TOKEN_ENV = "ASSISTANT_API_TOKEN".freeze

  def self.markdown
    new.markdown
  end

  def markdown
    <<~MD
      ## Seneschal Internal API

      All requests use:
      ```
      curl -s -H "Authorization: Bearer $#{TOKEN_ENV}" $#{BASE_ENV}/...
      ```

      ### Projects
      - `GET /projects` — list all projects
      - `GET /projects/:id` — get a project
      - `POST /projects` — create: `{"name":"X","repo_url":"Y","local_path":"Z"}`
      - `PATCH /projects/:id` — update fields

      ### Skills
      - `GET /skills` — list all skills
      - `GET /skills/:id` — get a skill
      - `POST /skills` — create: `{"name":"X","body":"...","description":"...","project_id":1}` (omit project_id for shared)
      - `PATCH /skills/:id` — update fields
      - `DELETE /skills/:id` — delete

      ### Workflows (scoped to project)
      - `GET /projects/:project_id/workflows` — list workflows for project
      - `GET /projects/:project_id/workflows/:id` — get a workflow
      - `POST /projects/:project_id/workflows` — create: `{"name":"X","trigger_type":"manual"}`
      - `PATCH /projects/:project_id/workflows/:id` — update
      - `DELETE /projects/:project_id/workflows/:id` — delete
      - `POST /projects/:project_id/workflows/:id/trigger` — trigger run (optional `input` hash)

      ### Steps (scoped to workflow)
      - `GET /projects/:project_id/workflows/:workflow_id/steps` — list steps
      - `POST /projects/:project_id/workflows/:workflow_id/steps` — create: `{"name":"X","step_type":"prompt","body":"..."}`
      - `PATCH /projects/:project_id/workflows/:workflow_id/steps/:id` — update
      - `DELETE /projects/:project_id/workflows/:workflow_id/steps/:id` — delete
      - `POST /projects/:project_id/workflows/:workflow_id/steps/reorder` — reorder: `{"steps":[{"id":1,"position":1}]}`

      ### Pipeline Tasks
      - `GET /pipeline_tasks` — list all tasks
      - `GET /pipeline_tasks/:id` — get a task
      - `POST /pipeline_tasks` — create: `{"title":"X","body":"...","kind":"feature","project_id":1}`
      - `PATCH /pipeline_tasks/:id` — update
      - `DELETE /pipeline_tasks/:id` — delete

      ### Page Context
      - `GET /page_contexts?path=/projects/1` — get context summary for a URL path

      ### UI Actions (use to interact with the user)
      - `POST /ui/navigate` — navigate user to a path: `{"path":"/projects/1"}`
      - `POST /ui/ask_choices` — show buttons: `{"prompt":"Pick one","choices":[{"label":"A","value":"a"}]}`
      - `POST /ui/ask_text` — ask freeform question: `{"prompt":"What should the workflow do?"}`

      ### Conversation State
      - `GET /conversation/state` — get current status and messages
      - `POST /conversation/finish_turn` — signal end of your turn (sets status to idle)

      ### Step Types
      Valid `step_type` values: `skill`, `script`, `command`, `ci_check`, `context_fetch`, `prompt`

      ### Workflow Trigger Types
      Valid `trigger_type` values: `manual`, `cron`, `file_watch`
    MD
  end
end
