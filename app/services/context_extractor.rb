class ContextExtractor
  def initialize(output_patterns, stdout)
    @output_patterns = output_patterns || {}
    @stdout = stdout || ""
  end

  def extract
    extracted = {}

    @output_patterns.each do |key, pattern|
      match = @stdout.match(Regexp.new(pattern))
      extracted[key.to_s] = match[1] if match
    end

    extracted
  end
end
