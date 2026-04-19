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
        handle(
          user_id: msg['from_id'],
          text: text,
          payload: parse_payload(msg['payload'])
        )
      end
    rescue StandardError => e
      puts "Loop error: #{e.message}, continuing..."
      sleep(2)
    end
  end

  private

  ##
  # This function retrieves the long poll server information for a VK group using the VK API.
  def get_long_poll_server
    vk_request('https://api.vk.com/method/groups.getLongPollServer', {
                 group_id: @group_id, access_token: @token, v: API_VERSION
               })&.dig('response')
  end

  ## Sends a message to a specified peer ID using the VK API with optional keyboard parameters.
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

  ##
  # The `allowed?` function checks if a user ID is included in a list of allowed users stored in the
  # environment variable `ALLOWED_USERS`.
  #
  # Args:
  #   user_id: The `allowed?` method checks if a given `user_id` is included in the list of allowed
  # users stored in the `ALLOWED_USERS` environment variable. The `user_id` parameter is the ID of the
  # user that you want to check for permission.
  def allowed?(user_id)
    allowed = ENV.fetch('ALLOWED_USERS', '').split(',').map(&:strip)
    allowed.include?(user_id.to_s)
  end

  ##
  # The `handle` function takes in user_id, text, and payload parameters, extracts the 'cmd' value
  # from the payload, and then delegates the handling based on the current state.
  def handle(user_id:, text:, payload:)
    cmd = payload&.dig('cmd')

    case @state
    when :idle then handle_idle(user_id, text, cmd)
    when :chatting then handle_chatting(user_id, text, cmd)
    when :selecting_session then handle_selecting_session(user_id, payload)
    when :confirming_clear then handle_confirming_clear(user_id, cmd)
    end
  end

  ##
  # The `parse_payload` function takes a raw input, attempts to parse it as JSON, and returns the
  # parsed result or `nil` if parsing fails.
  #
  # Args:
  #   raw: The `parse_payload` method takes a `raw` parameter, which is expected to be a JSON string.
  # The method attempts to parse this JSON string using `JSON.parse(raw)`. If parsing is successful,
  # it returns the parsed JSON object. If there is a `JSON::ParserError` (
  #
  # Returns:
  #   The `parse_payload` method will return the parsed JSON data if parsing is successful. If there
  # is a `JSON::ParserError` during parsing, it will return `nil`. If the `raw` input is `nil` or an
  # empty string, it will also return `nil`.
  def parse_payload(raw)
    return nil if raw.nil? || raw.to_s.empty?

    JSON.parse(raw)
  rescue JSON::ParserError
    nil
  end

  ##
  # The function checks the command or text input and performs different actions
  # based on the input.
  #
  # Args:
  #   user_id: User ID is a unique identifier for a specific user in the system. It is used to track
  # and manage user data and interactions.
  #   text: The `text` parameter in the `handle_idle` method is a string that represents the user
  # input or message received from the user. It is used in the method to determine the action to be
  # taken based on the user's input.
  #   cmd: The `cmd` parameter in the `handle_idle` method represents a command that the user has
  # entered. If no command is provided, it defaults to using the `text` parameter, which is the text
  # input from the user. The method then checks the command or text input to determine the appropriate
  # action
  def handle_idle(user_id, text, cmd)
    case cmd || text
    when 'new_session' then start_new_session(user_id)
    when 'my_sessions' then show_sessions(user_id)
    when '/start'      then show_main_menu(user_id, 'Привет! Выбери действие:')
    when 'status' then show_status(user_id)
    else show_main_menu(user_id, 'Выбери действие:')
    end
  end

  def show_status(user_id)
    text = @hermes.healthy? ? 'Hermes онлайн.' : 'Hermes недоступен.'
    send_message(user_id, text, main_keyboard)
  end

  ##
  # This function is named `handle_chatting` and takes three parameters: `user_id`, `text`, and
  # `cmd`.
  #
  # Args:
  #   user_id: A unique identifier for the user who is chatting.
  #   text: The `handle_chatting` function seems to be a function that handles chatting functionality.
  # It takes three parameters:
  #   cmd: The `handle_chatting` function seems to be a function that handles chatting functionality.
  # The parameters are:
  def handle_chatting(user_id, text, cmd)
    case cmd
    when 'main_menu'
      @state = :idle
      show_main_menu(user_id, 'Главное меню.')
    when 'clear_history'
      ask_confirm_clear(user_id)
    else
      chat(user_id, text)
    end
  end

  def show_main_menu(user_id, text)
    @state = :idle
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

  ##
  # Display sessions for a specific user based on their user ID
  def show_sessions(user_id)
    sessions = ChatSession.all.first(5)
    if sessions.empty?
      show_main_menu(user_id, 'Нет сохранённых диалогов.')
      return
    end
    @state = :selecting_session
    send_message(user_id, 'Выбери диалог:', sessions_keyboard(sessions))
  end

  def sessions_keyboard(sessions)
    rows = sessions.map { |s| [btn(s.name.slice(0, 40), 'select_session', 'secondary', extra: { id: s.id })] }
    rows << [btn('Главное меню', 'main_menu', 'negative')]
    { one_time: true, buttons: rows }
  end

  ##
  # Handles selecting a session for a specific user based on the provided user ID and
  # payload.
  def handle_selecting_session(user_id, payload)
    case payload&.dig('cmd')
    when 'select_session'
      @session = ChatSession.find(payload['id'])
      if @session
        @state = :chatting
        send_message(user_id, "Продолжаем «#{@session.name}».", chat_keyboard)
      else
        show_main_menu(user_id, 'Диалог не найден.')
      end
    when 'main_menu'
      show_main_menu(user_id, 'Главное меню.')
    else
      show_sessions(user_id)
    end
  end

  def handle_confirming_clear(user_id, cmd)
    case cmd
    when 'confirm_yes'
      @session.clear_messages
      @state = :chatting
      send_message(user_id, 'История очищена.', chat_keyboard)
    when 'confirm_no'
      @state = :chatting
      send_message(user_id, 'Отмена.', chat_keyboard)
    else
      ask_confirm_clear(user_id)
    end
  end

  def ask_confirm_clear(user_id)
    @state = :confirming_clear
    send_message(user_id, 'Очистить историю диалога?', confirm_keyboard)
  end

  def confirm_keyboard
    {
      one_time: true,
      buttons: [
        [btn('Да', 'confirm_yes', 'negative'), btn('Нет', 'confirm_no', 'positive')]
      ]
    }
  end

  ##
  # The `chat` function sends and receives messages in a chat interface, handling empty messages and
  # errors gracefully.
  #
  # Args:
  #   user_id: The `user_id` parameter in the `chat` method is used to identify the user to whom the
  # messages will be sent or received. It is typically a unique identifier for each user in the chat
  # system.
  #   text: The `text` parameter in the `chat` method represents the message input from the user that
  # will be processed by the chatbot. If the `text` is empty, the method will return a message saying
  # "Сообщение пустое"
  #
  # Returns:
  #   The `chat` method returns different responses based on the conditions:
  def chat(user_id, text)
    return send_message(user_id, 'Сообщение пустое.', chat_keyboard) if text.empty?

    @session.add_message('user', text)

    typing_thread = Thread.new do
      while Thread.current[:active]
        set_typing(user_id)
        sleep(8)
      end
    end
    typing_thread[:active] = true

    reply = @hermes.chat(@session.messages)
    typing_thread[:active] = false
    typing_thread.join

    @session.add_message('assistant', reply)
    send_message(user_id, strip_markdown(reply), chat_keyboard)
  rescue HermesClient::Error => e
    typing_thread&.kill
    send_message(user_id, "Ошибка Hermes: #{e.message}", chat_keyboard)
  rescue Faraday::TimeoutError
    typing_thread&.kill
    send_message(user_id, 'Hermes думает слишком долго, попробуй ещё раз.', chat_keyboard)
  end

  def chat_keyboard
    {
      one_time: false,
      buttons: [
        [btn('Очистить историю', 'clear_history', 'negative'), btn('Вернуться в меню', 'main_menu')]
      ]
    }
  end

  def start_new_session(user_id)
    name = "Диалог #{Time.now.strftime('%d.%m %H:%M')}"
    @session = ChatSession.create(name)
    @state = :chatting
    send_message(user_id, "Начат «#{name}».\nПиши вопрос!", chat_keyboard)
  end

  def strip_markdown(text)
    text
      .gsub(/\*\*(.*?)\*\*/, '\1') # **жирный**
      .gsub(/`(.*?)`/, '\1') # `код`
      .gsub(/^\#{2,6}\s/, '') # заголовки
  end

  # vk seems to have issues with tcp connection so we need to retry requests in case of errors
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
    retry if (retries -= 1) > 0
    nil
  end

  def poll(server:, key:, ts:)
    response = Faraday.new { |f| f.options.timeout = 30 }.get(server, act: 'a_check', key: key, ts: ts, wait: 25)
    JSON.parse(response.body)
  rescue Faraday::TimeoutError
    { 'updates' => [] }
  end

  def set_typing(peer_id)
    vk_request('https://api.vk.com/method/messages.setActivity', {
                 peer_id: peer_id,
                 type: 'typing',
                 access_token: @token,
                 v: API_VERSION
               })
  end
end
