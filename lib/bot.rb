# frozen_string_literal: true

require 'faraday'
require 'json'
require_relative 'hermes_client'
require_relative 'chat_session'
require_relative 'states/base_state'
require_relative 'states/idle_state'
require_relative 'states/chatting_state'
require_relative 'states/selecting_session_state'
require_relative 'states/confirming_clear_state'

class Bot
  # VK API constants.
  VK_API = 'https://api.vk.com/method/'
  API_VERSION = '5.131'

  attr_accessor :state, :session
  attr_reader :hermes

  def initialize(vk_token:, vk_group_id:, hermes_client:)
    @token = vk_token
    @group_id = vk_group_id
    @hermes = hermes_client
    @state = :idle
    @session = nil
    @state = States::IdleState.new(self)
  end

  def run
    ChatSession.setup_db
    # Persisted state is restored for the first allowed user.
    allowed_user = ENV.fetch('ALLOWED_USERS', '').split(',').first&.strip&.to_i
    restore_state(allowed_user) if allowed_user
    lp = get_long_poll_server
    server = lp['server']
    key = lp['key']
    ts = lp['ts']
    # Basic startup log for local debugging.
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

        # Delegate user input handling to the current FSM state.
        @state.handle(msg['from_id'], text, parse_payload(msg['payload']))
      end
    rescue StandardError => e
      puts "Loop error: #{e.message}, continuing..."
      sleep(2)
    end
  end

  # Sends a message to VK with an optional keyboard payload.
  def send_message(peer_id, text, keyboard = nil)
    params = {
      peer_id: peer_id,
      message: text,
      random_id: rand(1_000_000),
      access_token: @token,
      v: API_VERSION
    }
    params[:keyboard] = JSON.dump(keyboard) if keyboard
    vk_request('https://api.vk.com/method/messages.send', params)
  end

  def show_main_menu(user_id, text)
    @state = States::IdleState.new(self)
    send_message(user_id, text, main_keyboard)
  end

  def main_keyboard
    {
      one_time: false,
      buttons: [
        [btn('Новый диалог', 'new_session', 'positive'), btn('Мои диалоги', 'my_sessions')],
        [btn('Статус Hermes', 'status')]
      ]
    }
  end

  def btn(label, cmd, color = 'secondary', extra: {})
    { action: { type: 'text', label: label, payload: JSON.dump({ cmd: cmd, **extra }) }, color: color }
  end

  def confirm_keyboard
    {
      one_time: true,
      buttons: [
        [btn('Да', 'confirm_yes', 'negative'), btn('Нет', 'confirm_no', 'positive')]
      ]
    }
  end

  def chat_keyboard
    {
      one_time: false,
      buttons: [
        [btn('Очистить историю', 'clear_history', 'negative'), btn('Вернуться в меню', 'main_menu')]
      ]
    }
  end

  def set_typing(peer_id)
    vk_request('https://api.vk.com/method/messages.setActivity', {
                 peer_id: peer_id,
                 type: 'typing',
                 access_token: @token,
                 v: API_VERSION
               })
  end

  def sessions_keyboard(sessions)
    rows = sessions.map { |s| [btn(s.name.slice(0, 40), 'select_session', 'secondary', extra: { id: s.id })] }
    rows << [btn('Главное меню', 'main_menu', 'negative')]
    { one_time: true, buttons: rows }
  end

  def strip_markdown(text)
    text
      .gsub(/\*\*(.*?)\*\*/, '\1') # **жирный**
      .gsub(/`(.*?)`/, '\1') # `код`
      .gsub(/^\#{2,6}\s/, '') # заголовки
  end

  private

  def restore_state(user_id)
    data = ChatSession.load_state(user_id)
    @session = data[:session_id] ? ChatSession.find(data[:session_id]) : nil
    @state = case data[:state]
             when 'chatting'          then States::ChattingState.new(self)
             when 'selectingsession'  then States::SelectingSessionState.new(self)
             when 'confirmingclear'   then States::ConfirmingClearState.new(self)
             else States::IdleState.new(self)
             end
  end

  def get_long_poll_server
    vk_request('https://api.vk.com/method/groups.getLongPollServer', {
                 group_id: @group_id, access_token: @token, v: API_VERSION
               })&.dig('response')
  end

  # Checks whether user is in the allowlist from ALLOWED_USERS.
  def allowed?(user_id)
    allowed = ENV.fetch('ALLOWED_USERS', '').split(',').map(&:strip)
    allowed.include?(user_id.to_s)
  end

  # Parses VK payload JSON; returns nil for empty or invalid payload.
  def parse_payload(raw)
    return nil if raw.nil? || raw.to_s.empty?

    JSON.parse(raw)
  rescue JSON::ParserError
    nil
  end

  # Retries VK request because long poll API occasionally returns transient errors.
  def vk_request(url, params, retries: 3)
    retries.times do |i|
      response = Faraday.new { |f| f.options.timeout = 3 }.get(url, params)
      body = JSON.parse(response.body)
      return body unless body['error']

      puts "VK error: #{body['error']['error_msg']}, retry #{i + 1}/#{retries}"
      sleep(1)
    end
    nil
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
    puts "Connection error: #{e.message}, retry..."
    retry if (retries -= 1).positive?
    nil
  end

  def poll(server:, key:, ts:)
    response = Faraday.new { |f| f.options.timeout = 30 }.get(server, act: 'a_check', key: key, ts: ts, wait: 25)
    JSON.parse(response.body)
  rescue Faraday::TimeoutError
    { 'updates' => [] }
  end
end
