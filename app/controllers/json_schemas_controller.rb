class JsonSchemasController < ApplicationController
  before_action :set_schema, only: [:show, :edit, :update, :destroy]

  def index
    @schemas = JsonSchema.order(:name)
    @usage_counts = Step.where("json_extract(config, '$.json_schema_id') IS NOT NULL")
                        .group("json_extract(config, '$.json_schema_id')")
                        .count
  end

  def show; end

  def new
    @schema = JsonSchema.new
  end

  def edit; end

  def create
    @schema = JsonSchema.new(schema_params)
    if @schema.save
      redirect_to @schema, notice: "Schema created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @schema.update(schema_params)
      redirect_to @schema, notice: "Schema updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @schema.referencing_steps.exists?
      redirect_to json_schemas_path, alert: "Cannot delete schema '#{@schema.name}' — it is referenced by one or more steps."
    else
      @schema.destroy
      redirect_to json_schemas_path, notice: "Schema deleted."
    end
  end

  private

  def set_schema
    @schema = JsonSchema.find(params[:id])
  end

  def schema_params
    params.expect(json_schema: [:name, :description, :body])
  end
end
