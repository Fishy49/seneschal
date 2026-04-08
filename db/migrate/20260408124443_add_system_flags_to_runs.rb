class AddSystemFlagsToRuns < ActiveRecord::Migration[8.1]
  # Stub model isolated from app/models so the migration is stable even if
  # the Run class gains validations or callbacks later.
  class MigrationRun < ActiveRecord::Base
    self.table_name = "runs"
  end

  def up
    add_column :runs, :system_flags, :json, default: {}, null: false

    # Move any existing auto_recovered flags out of user context into system_flags.
    MigrationRun.reset_column_information
    MigrationRun.find_each do |run|
      next unless run.context.is_a?(Hash) && run.context.key?("auto_recovered")

      ctx = run.context.dup
      flag = ctx.delete("auto_recovered")
      run.update!(context: ctx, system_flags: { "auto_recovered" => flag })
    end
  end

  def down
    remove_column :runs, :system_flags
  end
end
