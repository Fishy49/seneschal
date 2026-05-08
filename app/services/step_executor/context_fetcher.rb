require "net/http"
require "uri"

class StepExecutor
  module ContextFetcher
    private

    def execute_context_fetch(&)
      cfg = @step.config
      method = cfg.fetch("method", "url")

      case method
      when "url" then fetch_url(cfg, &)
      when "project_file" then fetch_project_file(cfg, &)
      else
        Result.new(exit_code: 1, stdout: "", stderr: "Unknown context_fetch method: #{method}")
      end
    rescue StandardError => e
      Result.new(exit_code: 1, stdout: "", stderr: e.message)
    end

    def fetch_project_file(cfg)
      raw_path = interpolate_string(cfg.fetch("path", ""))
      return Result.new(exit_code: 1, stdout: "", stderr: "No file path provided") if raw_path.blank?

      base = File.expand_path(@repo_path.to_s)
      resolved = File.expand_path(raw_path, base)
      unless resolved.start_with?(base + File::SEPARATOR) || resolved == base
        return Result.new(exit_code: 1, stdout: "", stderr: "Path '#{raw_path}' escapes the project directory")
      end
      return Result.new(exit_code: 1, stdout: "", stderr: "File not found: #{raw_path}") unless File.file?(resolved)

      yield({ output: "Reading #{raw_path}..." }) if block_given?
      content = File.read(resolved)
      yield({ output: content }) if block_given?
      Result.new(exit_code: 0, stdout: content, stderr: "")
    end

    def fetch_url(cfg)
      raw_url = interpolate_string(cfg.fetch("url", ""))
      return Result.new(exit_code: 1, stdout: "", stderr: "No URL provided") if raw_url.blank?

      resolved_url = resolve_smart_url(raw_url)
      yield({ output: "Fetching #{resolved_url}..." }) if block_given?

      uri = URI.parse(resolved_url)
      content = fetch_with_redirects(uri)

      yield({ output: content }) if block_given?
      Result.new(exit_code: 0, stdout: content, stderr: "")
    end

    # Converts GitHub repo/blob URLs into raw content URLs
    def resolve_smart_url(url)
      case url
      when %r{\Ahttps?://github\.com/([^/]+/[^/]+?)(?:\.git)?/?\z}
        "https://raw.githubusercontent.com/#{::Regexp.last_match(1)}/HEAD/README.md"
      when %r{\Ahttps?://github\.com/([^/]+/[^/]+)/blob/(.+)\z}
        "https://raw.githubusercontent.com/#{::Regexp.last_match(1)}/#{::Regexp.last_match(2)}"
      else
        url
      end
    end

    def fetch_with_redirects(uri, limit = 5)
      raise "Too many redirects" if limit.zero?

      response = Net::HTTP.get_response(uri)
      case response
      when Net::HTTPSuccess
        response.body
      when Net::HTTPRedirection
        fetch_with_redirects(URI.parse(response["location"]), limit - 1)
      else
        raise "HTTP #{response.code}: #{response.message}"
      end
    end
  end
end
