namespace :seneschal do
  desc "One-shot post-deploy migration for the agent-runtime refactor. Idempotent; safe to re-run. " \
       "Recommended deploy order: stop workers → deploy code → db:migrate → mega_update → restart workers. " \
       "ENV toggles: DRY_RUN=1 (preview only), STALE_MINUTES=N (hung-run threshold; default 30)."
  task mega_update: :environment do
    summary = MegaUpdate.call(
      dry_run: ENV["DRY_RUN"] == "1",
      stale_minutes: (ENV["STALE_MINUTES"].presence || MegaUpdate::DEFAULT_STALE_MINUTES.to_s).to_i
    )

    exit(1) if summary.aborted
  end
end
