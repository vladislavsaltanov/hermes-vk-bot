# frozen_string_literal: true

module States
  class ChattingState < BaseState
    def handle(user_id, text, payload)
      cmd = payload&.dig('cmd')

      case cmd
      when 'main_menu'
        transition_to(IdleState, user_id)
        @bot.show_main_menu(user_id, 'Главное меню.')
      when 'clear_history'
        transition_to(ConfirmingClearState, user_id)
        @bot.send_message(user_id, 'Очистить историю диалога?', @bot.confirm_keyboard)
      else
        chat(user_id, text)
      end
    end

    private

    def chat(user_id, text)
      return @bot.send_message(user_id, 'Сообщение пустое.', @bot.chat_keyboard) if text.empty?

      # Typing indicator is sent in a separate loop while Hermes is processing.
      typing_thread = start_typing(user_id)
      @bot.session.add_message('user', text)
      reply = @bot.hermes.chat(@bot.session.messages)
      stop_typing(typing_thread)
      @bot.session.add_message('assistant', reply)
      @bot.send_message(user_id, @bot.strip_markdown(reply), @bot.chat_keyboard)
    rescue HermesClient::Error => e
      stop_typing(typing_thread)
      @bot.send_message(user_id, "Ошибка Hermes: #{e.message}", @bot.chat_keyboard)
    rescue Faraday::TimeoutError
      stop_typing(typing_thread)
      @bot.send_message(user_id, 'Hermes думает слишком долго, попробуй ещё раз.', @bot.chat_keyboard)
    end

    def start_typing(user_id)
      # VK expects activity updates periodically, otherwise typing status disappears.
      thread = Thread.new do
        while Thread.current[:active]
          @bot.set_typing(user_id)
          sleep(8)
        end
      end
      thread[:active] = true
      thread
    end

    def stop_typing(thread)
      return unless thread

      thread[:active] = false
      thread.join
    end
  end
end
