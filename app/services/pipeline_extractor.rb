class PipelineExtractor
  # Extracts declared output variables from step results.
  #
  # For AI steps (skill/prompt):
  #   Parses ```output blocks from the result text
  #
  # For script/command steps:
  #   Parses ::set-output name=value lines from stdout
  #
  # For context_fetch steps:
  #   Stores fetched content under the configured context_key

  def initialize(step, stdout)
    @step = step
    @stdout = stdout || ""
  end

  def extract
    case @step.step_type
    when "skill", "prompt"
      extract_output_block
    when "script", "command"
      extract_set_output
    when "context_fetch"
      key = @step.config["context_key"]
      key.present? ? { key => @stdout } : {}
    when "json_validator"
      {}
    else
      {}
    end
  end

  def validate_produces
    @step.produces - extract.keys
  end

  private

  def extract_output_block
    extracted = {}

    @stdout.scan(/```output\s*\n(.*?)```/m) do |match|
      lines = match[0].lines
      i = 0
      while i < lines.size
        line = lines[i].rstrip
        stripped = line.lstrip
        i += 1

        # Match "key: |" (multiline) or "key: value" (single-line)
        if (m = stripped.match(/\A(\w+):\s*\|\s*\z/))
          key = m[1]
          value_lines = []
          # Collect lines that are indented more than the key line, or blank
          key_indent = line.length - stripped.length
          while i < lines.size
            next_line = lines[i]
            next_stripped = next_line.rstrip
            next_indent = next_stripped.empty? ? key_indent + 2 : next_line.length - next_line.lstrip.length
            break if !next_stripped.empty? && next_indent <= key_indent

            value_lines << next_stripped.lstrip
            i += 1
          end
          extracted[key] = value_lines.join("\n").strip
        elsif (m = stripped.match(/\A(\w+):\s*(.+)\z/))
          extracted[m[1]] = m[2].strip
        end
      end
    end

    extracted
  end

  def extract_set_output
    extracted = {}

    @stdout.each_line do |line|
      if (m = line.strip.match(/\A::set-output\s+(\w+)=(.+)\z/))
        extracted[m[1]] = m[2].strip
      end
    end

    extracted
  end
end
