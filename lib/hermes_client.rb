# frozen_string_literal: true

require 'faraday'
require 'json'

class HermesClient # rubocop:disable Style/Documentation
  class Error < StandardError; end

  def
  # when a new instance of the class is created. It takes two keyword arguments `base_url` and
  # `api_key`, which are used to set up a connection to the specified base URL with the provided
  # API key.
  initialize(base_url:, api_key:)
    @conn = Faraday.new(url: base_url) do |f|
      f.headers['Authorization'] = "Bearer #{api_key}"
      f.headers['Content-Type'] = 'application/json'
      f.options.timeout = 300 # 5 минут на ответ
      f.options.open_timeout = 10 # 10 секунд на соединение
    end
  end

  ##
  # Sends messages to a chat API endpoint and returns the response content from
  # the first choice.
  # Args:
  #   messages: The `messages` parameter in the `chat` method is expected to be an array of messages
  # that will be sent to the chat service for processing. Each message in the array should be a string
  # representing a part of the conversation.
  def chat(messages)
    response = @conn.post('/v1/chat/completions') do |req|
      req.body = JSON.dump({ model: 'hermes-agent', messages: messages })
    end
    raise Error, "HTTP #{response.status}" unless response.status == 200

    JSON.parse(response.body).dig('choices', 0, 'message', 'content') ||
      raise(Error, 'Empty response')
  end

  ##
  # Checks if a connection to a health endpoint returns a status code of 200
  # and returns true if successful, otherwise false.
  def healthy?
    @conn.get('/health').status == 200
  rescue StandardError
    false
  end
end
