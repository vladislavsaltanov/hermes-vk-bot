# frozen_string_literal: true

require 'faraday'
require 'json'
require_relative 'hermes_client'
require_relative 'chat_session'

class Bot
  # constants for VK API
  VK_API = 'https://api.vk.com/method/'
  API_VERSION = '5.131'

  def initialize(vk_token:, vk_group_id:, hermes_client:)
    @token = vk_token
    @group_id = vk_group_id
    @hermes = hermes_client
    @state = :idle
    @session = nil
  end

  def run
    ChatSession.setup_db
    lp = get_long_poll_server
    server = lp['server']
    key = lp['key']
    ts = lp['ts']
    # logs
    puts 'Bot started.'

    loop do
      result = poll(server: server, key: key, ts: ts)
      ts = result['ts']

      (result['updates'] || []).each do |update|
        next unless update['type'] == 'message_new'

        msg = update.dig('object', 'message')
        next unless msg
        # ignore group chat messages
        next if msg['from_id'].to_i.negative?
        # ignore messages from users not in the allowed list
        next unless allowed?(msg['from_id'])

        text = msg['text'].to_s.strip
        # ignore empty messages
        next if text.empty?

        # sending message to the Hermes agent and getting a reply
        reply = @hermes.chat([{ role: 'user', content: text }])
        # sending the reply back to the user
        send_message(msg['from_id'], reply)
      end
    end
  end

  private

  ##
  # This function retrieves the long poll server information for a VK group using the VK API.
  def get_long_poll_server
    res = Faraday.get('https://api.vk.com/method/groups.getLongPollServer', {
                        group_id: @group_id,
                        access_token: @token,
                        v: API_VERSION
                      })
    JSON.parse(res.body)['response']
  end

  ##
  # The `poll` function sends a request to a server with specified parameters and returns the parsed
  # JSON response.
  def poll(server:, key:, ts:)
    JSON.parse(Faraday.get(server, act: 'a_check', key: key, ts: ts, wait: 25).body)
  end

  ## The `send_message` function sends a message to a specified peer ID using the VK API with the
  def send_message(peer_id, text)
    Faraday.get('https://api.vk.com/method/messages.send', {
                  peer_id: peer_id,
                  message: text,
                  random_id: rand(1_000_000),
                  access_token: @token,
                  v: API_VERSION
                })
  end

  def allowed?(user_id)
    allowed = ENV.fetch('ALLOWED_USERS', '').split(',').map(&:strip)
    allowed.include?(user_id.to_s)
  end
end
