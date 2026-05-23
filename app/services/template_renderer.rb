class TemplateRenderer
  def initialize(body, context)
    @body = body
    @context = context.transform_keys(&:to_sym)
  end

  def render
    @body.gsub(/\$\{(\w+)\}/) do
      key = ::Regexp.last_match(1).to_sym
      if @context.key?(key)
        # Hash / Array context values (parsed structured_output payloads)
        # must render as JSON rather than Ruby's `Hash#to_s` (`{"a"=>1}`)
        # so prompt bodies stay readable and machine-consumable.
        JsonPathResolver.format(@context[key])
      else
        "${#{::Regexp.last_match(1)}}"
      end
    end
  end
end
