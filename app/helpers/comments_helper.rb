module CommentsHelper
  # Escapes the body, then tints @mention tokens. There is no shared markdown
  # renderer in this app (the markdown Stimulus controller only syntax-
  # highlights source), so comments render as escaped plain text.
  def highlight_mentions(body)
    escaped = ERB::Util.html_escape(body.to_s)
    escaped.gsub(Comment::MENTION_PATTERN) do
      tag.span(Regexp.last_match(0), class: "text-accent font-medium")
    end.html_safe # rubocop:disable Rails/OutputSafety
  end
end
