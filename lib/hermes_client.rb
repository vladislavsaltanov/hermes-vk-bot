# frozen_string_literal: true

require 'faraday'
require 'json'

class HermesClient
  class Error < StandardError; end

  # Prepares persistent HTTP connection with auth and timeouts.
  def initialize(base_url:, api_key:)
    @conn = Faraday.new(url: base_url) do |f|
      f.headers['Authorization'] = "Bearer #{api_key}" unless api_key.to_s.strip.empty?
      f.headers['Content-Type'] = 'application/json'
      f.options.timeout = 300 # 5 минут на ответ
      f.options.open_timeout = 10 # 10 секунд на соединение
    end
  end

  # Sends chat history and returns assistant text from first choice.
  def chat(messages)
    response = @conn.post('/v1/chat/completions') do |req|
      req.body = JSON.dump({ model: 'hermes-agent', messages: messages })
    end
    raise Error, "HTTP #{response.status}" unless response.status == 200

    JSON.parse(response.body).dig('choices', 0, 'message', 'content') ||
      raise(Error, 'Empty response')
  end

  def chat_streaming(messages, &on_chunk)
    @conn.post('/v1/chat/completions') do |req|
      req.body = JSON.dump({ model: 'hermes-agent', messages: messages, stream: true })
      req.options.on_data = proc do |chunk, _bytes|
        chunk.split("\n").each do |line|
          next unless line.start_with?('data: ')

          data = line[6..]
          next if data == '[DONE]'

          parsed = JSON.parse(data)
          token = parsed.dig('choices', 0, 'delta', 'content')
          on_chunk.call(token) if token
        rescue JSON::ParserError
          nil
        end
      end
    end
  end

  # Health check used in the bot status command.
  def healthy?
    @conn.get('/health').status == 200
  rescue StandardError
    false
  end
end
