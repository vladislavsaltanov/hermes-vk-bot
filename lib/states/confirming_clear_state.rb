# frozen_string_literal: true

module States
  class ConfirmingClearState < BaseState
    def handle(user_id, _text, payload)
      case payload&.dig('cmd')
      when 'confirm_yes'
        @bot.session.clear_messages
        transition_to(ChattingState, user_id)
        @bot.send_message(user_id, 'История очищена.', @bot.chat_keyboard)
      when 'confirm_no'
        transition_to(ChattingState, user_id)
        @bot.send_message(user_id, 'Отмена.', @bot.chat_keyboard)
      else
        @bot.send_message(user_id, 'Очистить историю диалога?', @bot.confirm_keyboard)
      end
    end
  end
end
