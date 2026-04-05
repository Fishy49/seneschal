class TemplateRenderer
  def initialize(body, context)
    @body = body
    @context = context.transform_keys(&:to_sym)
  end

  def render
    @body.gsub(/\$\{(\w+)\}/) do
      key = ::Regexp.last_match(1).to_sym
      @context.fetch(key) { "${#{::Regexp.last_match(1)}}" }
    end
  end
end
