# frozen_string_literal: true

module States
  class SelectingSessionState < BaseState
    def handle(user_id, _text, payload)
      case payload&.dig('cmd')
      when 'select_session'
        session = ChatSession.find(payload['id'])
        if session
          @bot.session = session
          transition_to(ChattingState, user_id)
          @bot.send_message(user_id, "Продолжаем «#{session.name}».", @bot.chat_keyboard)
        else
          @bot.show_main_menu(user_id, 'Диалог не найден.')
        end
      when 'delete_session'
        session = ChatSession.find(payload['id'])
        session&.destroy
        show_sessions(user_id)
      when 'main_menu'
        transition_to(IdleState, user_id)
        @bot.show_main_menu(user_id, 'Главное меню.')
      else
        show_sessions(user_id)
      end
    end

    private

    def show_sessions(user_id)
      sessions = ChatSession.all.first(5)
      if sessions.empty?
        transition_to(IdleState, user_id)
        @bot.show_main_menu(user_id, 'Нет сохранённых диалогов.')
        return
      end
      @bot.send_message(user_id, 'Выбери диалог:', @bot.sessions_keyboard(sessions))
    end
  end
end
