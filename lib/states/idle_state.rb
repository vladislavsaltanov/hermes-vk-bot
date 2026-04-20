# frozen_string_literal: true

module States
  class IdleState < BaseState
    def handle(user_id, text, payload)
      # Commands can come either from button payload or plain text.
      cmd = payload&.dig('cmd') || text

      case cmd
      when 'new_session' then start_new_session(user_id)
      when 'my_sessions' then show_sessions(user_id)
      when 'status' then show_status(user_id)
      when '/start', 'Привет', 'привет' then @bot.show_main_menu(user_id, 'Привет! Выбери действие:')
      else @bot.show_main_menu(user_id, 'Выбери действие:')
      end
    end

    private

    def start_new_session(user_id)
      name = "Диалог #{Time.now.strftime('%d.%m %H:%M')}"
      @bot.session = ChatSession.create(name)
      transition_to(ChattingState, user_id)
      @bot.send_message(user_id, "Начат «#{name}».\nПиши вопрос!", @bot.chat_keyboard)
    end

    def show_sessions(user_id)
      # Show only the latest sessions to keep keyboard compact.
      sessions = ChatSession.all.first(5)
      if sessions.empty?
        @bot.show_main_menu(user_id, 'Нет сохранённых диалогов.')
        return
      end
      transition_to(SelectingSessionState, user_id)
      @bot.send_message(user_id, 'Выбери диалог:', @bot.sessions_keyboard(sessions))
    end

    def show_status(user_id)
      text = @bot.hermes.healthy? ? 'Hermes онлайн.' : 'Hermes недоступен.'
      @bot.send_message(user_id, text, @bot.main_keyboard)
    end
  end
end
