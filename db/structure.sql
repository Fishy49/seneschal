CREATE TABLE IF NOT EXISTS "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE IF NOT EXISTS "projects" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "repo_url" varchar NOT NULL, "local_path" varchar NOT NULL, "description" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "repo_status" varchar DEFAULT 'not_cloned' NOT NULL);
CREATE TABLE IF NOT EXISTS "workflows" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "description" text, "trigger_type" varchar DEFAULT 'manual' NOT NULL, "trigger_config" json, "project_id" integer NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_382d2c48c7"
FOREIGN KEY ("project_id")
  REFERENCES "projects" ("id")
);
CREATE INDEX "index_workflows_on_project_id" ON "workflows" ("project_id");
CREATE TABLE IF NOT EXISTS "run_steps" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "status" varchar DEFAULT 'pending' NOT NULL, "attempt" integer DEFAULT 1 NOT NULL, "output" text, "error_output" text, "exit_code" integer, "started_at" datetime(6), "finished_at" datetime(6), "duration" float, "run_id" integer NOT NULL, "step_id" integer NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "position" integer, "resolved_input_context" text, "stream_log" json, "claude_session_id" varchar, "parent_run_step_id" integer, CONSTRAINT "fk_rails_154ec68049"
FOREIGN KEY ("run_id")
  REFERENCES "runs" ("id")
, CONSTRAINT "fk_rails_58f100d30f"
FOREIGN KEY ("step_id")
  REFERENCES "steps" ("id")
);
CREATE INDEX "index_run_steps_on_run_id" ON "run_steps" ("run_id");
CREATE INDEX "index_run_steps_on_step_id" ON "run_steps" ("step_id");
CREATE TABLE IF NOT EXISTS "skills" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "description" text, "body" text NOT NULL, "project_id" integer, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_ca04e2fd46"
FOREIGN KEY ("project_id")
  REFERENCES "projects" ("id")
);
CREATE INDEX "index_skills_on_project_id" ON "skills" ("project_id");
CREATE TABLE IF NOT EXISTS "pipeline_tasks" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "title" varchar NOT NULL, "body" text NOT NULL, "kind" varchar DEFAULT 'feature' NOT NULL, "status" varchar DEFAULT 'draft' NOT NULL, "project_id" integer NOT NULL, "workflow_id" integer, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "archived_at" datetime(6), "context_files" json DEFAULT '[]', "trigger_type" varchar DEFAULT 'manual' NOT NULL, "trigger_config" json DEFAULT '{}' NOT NULL, CONSTRAINT "fk_rails_03c1924935"
FOREIGN KEY ("project_id")
  REFERENCES "projects" ("id")
, CONSTRAINT "fk_rails_dca9f3bfcd"
FOREIGN KEY ("workflow_id")
  REFERENCES "workflows" ("id")
);
CREATE INDEX "index_pipeline_tasks_on_project_id" ON "pipeline_tasks" ("project_id");
CREATE INDEX "index_pipeline_tasks_on_workflow_id" ON "pipeline_tasks" ("workflow_id");
CREATE TABLE IF NOT EXISTS "runs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "status" varchar DEFAULT 'pending' NOT NULL, "context" json DEFAULT '{}' NOT NULL, "input" json DEFAULT '{}' NOT NULL, "started_at" datetime(6), "finished_at" datetime(6), "error_message" text, "workflow_id" integer NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "pipeline_task_id" integer, "system_flags" json DEFAULT '{}' NOT NULL, CONSTRAINT "fk_rails_404232665a"
FOREIGN KEY ("workflow_id")
  REFERENCES "workflows" ("id")
, CONSTRAINT "fk_rails_fe71673043"
FOREIGN KEY ("pipeline_task_id")
  REFERENCES "pipeline_tasks" ("id")
);
CREATE INDEX "index_runs_on_workflow_id" ON "runs" ("workflow_id");
CREATE INDEX "index_runs_on_pipeline_task_id" ON "runs" ("pipeline_task_id");
CREATE TABLE IF NOT EXISTS "users" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "email" varchar NOT NULL, "password_digest" varchar NOT NULL, "otp_secret" varchar, "otp_required_for_login" boolean DEFAULT FALSE NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "admin" boolean DEFAULT FALSE NOT NULL, "invite_token" varchar, "invite_accepted_at" datetime(6));
CREATE UNIQUE INDEX "index_users_on_email" ON "users" ("email");
CREATE TABLE IF NOT EXISTS "settings" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "key" varchar NOT NULL, "value" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_settings_on_key" ON "settings" ("key");
CREATE UNIQUE INDEX "index_users_on_invite_token" ON "users" ("invite_token");
CREATE TABLE IF NOT EXISTS "code_maps" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "project_id" integer NOT NULL, "tree" json DEFAULT '[]' NOT NULL, "modules" json DEFAULT '[]' NOT NULL, "file_index" json DEFAULT '{}' NOT NULL, "status" varchar DEFAULT 'pending' NOT NULL, "error_message" text, "commit_sha" varchar, "file_count" integer DEFAULT 0, "generated_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_f0fcdf3e2b"
FOREIGN KEY ("project_id")
  REFERENCES "projects" ("id")
);
CREATE UNIQUE INDEX "index_code_maps_on_project_id" ON "code_maps" ("project_id");
CREATE VIRTUAL TABLE code_map_search USING fts5(
  path,
  summary,
  module_name,
  language,
  code_map_id UNINDEXED,
  tokenize='porter unicode61'
)
/* code_map_search(path,summary,module_name,language,code_map_id) */;
CREATE TABLE IF NOT EXISTS 'code_map_search_data'(id INTEGER PRIMARY KEY, block BLOB);
CREATE TABLE IF NOT EXISTS 'code_map_search_idx'(segid, term, pgno, PRIMARY KEY(segid, term)) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS 'code_map_search_content'(id INTEGER PRIMARY KEY, c0, c1, c2, c3, c4);
CREATE TABLE IF NOT EXISTS 'code_map_search_docsize'(id INTEGER PRIMARY KEY, sz BLOB);
CREATE TABLE IF NOT EXISTS 'code_map_search_config'(k PRIMARY KEY, v) WITHOUT ROWID;
CREATE INDEX "index_run_steps_on_parent_run_step_id" ON "run_steps" ("parent_run_step_id");
CREATE TABLE IF NOT EXISTS "steps" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "position" integer NOT NULL, "step_type" varchar NOT NULL, "config" json DEFAULT '{}' NOT NULL, "max_retries" integer DEFAULT 0 NOT NULL, "timeout" integer DEFAULT 600 NOT NULL, "workflow_id" integer, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "skill_id" integer, "body" text, "input_context" text, "run_id" integer, CONSTRAINT "fk_rails_294a432e06"
FOREIGN KEY ("run_id")
  REFERENCES "runs" ("id")
, CONSTRAINT "fk_rails_cc243573db"
FOREIGN KEY ("skill_id")
  REFERENCES "skills" ("id")
, CONSTRAINT "fk_rails_db4a595a96"
FOREIGN KEY ("workflow_id")
  REFERENCES "workflows" ("id")
);
CREATE INDEX "index_steps_on_workflow_id" ON "steps" ("workflow_id");
CREATE INDEX "index_steps_on_skill_id" ON "steps" ("skill_id");
CREATE INDEX "index_steps_on_run_id" ON "steps" ("run_id");
CREATE TABLE IF NOT EXISTS "step_templates" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "step_type" varchar NOT NULL, "body" text, "config" json DEFAULT '{}' NOT NULL, "skill_id" integer, "max_retries" integer DEFAULT 0 NOT NULL, "timeout" integer DEFAULT 600 NOT NULL, "input_context" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_4a070dc96b"
FOREIGN KEY ("skill_id")
  REFERENCES "skills" ("id")
);
CREATE INDEX "index_step_templates_on_skill_id" ON "step_templates" ("skill_id");
CREATE UNIQUE INDEX "index_step_templates_on_name" ON "step_templates" ("name");
CREATE INDEX "index_pipeline_tasks_on_trigger_type" ON "pipeline_tasks" ("trigger_type");
CREATE TABLE IF NOT EXISTS "assistant_conversations" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "user_id" integer NOT NULL, "project_id" integer, "claude_session_id" varchar, "status" varchar DEFAULT 'idle', "last_page_path" varchar, "title" varchar, "turbo_token" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_e0922243f0"
FOREIGN KEY ("user_id")
  REFERENCES "users" ("id")
 ON DELETE CASCADE, CONSTRAINT "fk_rails_8051ba0da6"
FOREIGN KEY ("project_id")
  REFERENCES "projects" ("id")
 ON DELETE CASCADE);
CREATE INDEX "index_assistant_conversations_on_user_id_and_updated_at" ON "assistant_conversations" ("user_id", "updated_at");
CREATE TABLE IF NOT EXISTS "assistant_messages" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "assistant_conversation_id" integer NOT NULL, "role" varchar, "content" text, "choices" json DEFAULT '[]', "events" json DEFAULT '[]', "turbo_token" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_86abdd5953"
FOREIGN KEY ("assistant_conversation_id")
  REFERENCES "assistant_conversations" ("id")
 ON DELETE CASCADE);
CREATE INDEX "idx_on_assistant_conversation_id_created_at_852c40592e" ON "assistant_messages" ("assistant_conversation_id", "created_at");
INSERT INTO "schema_migrations" (version) VALUES
('20260420000002'),
('20260420000001'),
('20260419025604'),
('20260417141730'),
('20260413044358'),
('20260413025821'),
('20260413025756'),
('20260413025514'),
('20260411052806'),
('20260410050331'),
('20260408124443'),
('20260406000947'),
('20260405182138'),
('20260405044555'),
('20260405005838'),
('20260405002114'),
('20260404221210'),
('20260404190638'),
('20260404024152'),
('20260403210000'),
('20260403170906'),
('20260403170836'),
('20260403151513'),
('20260403151443'),
('20260403044806'),
('20260403044805'),
('20260403044804'),
('20260403044803'),
('20260403044802');

