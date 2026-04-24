# frozen_string_literal: true

module States
  class ChattingState < BaseState
    def handle(user_id, text, payload)
      # Button payload commands have priority over free-form text input.
      cmd = payload&.dig('cmd')

      case cmd
      when 'stop_request'
        @bot.cancel_inflight(user_id)
        @bot.send_message(user_id, 'Запрос остановлен.', @bot.chat_keyboard)
      when 'main_menu'
        @bot.cancel_inflight(user_id)
        transition_to(IdleState, user_id)
        @bot.show_main_menu(user_id, 'Главное меню.')
      when 'clear_history'
        @bot.cancel_inflight(user_id)
        transition_to(ConfirmingClearState, user_id)
        @bot.send_message(user_id, 'Очистить историю диалога?', @bot.confirm_keyboard)
      else
        start_chat_async(user_id, text)
      end
    end

    private

    def start_chat_async(user_id, text)
      # Fast-fail on invalid input and duplicate in-flight requests.
      return @bot.send_message(user_id, 'Сообщение пустое.', @bot.chat_keyboard) if text.empty?
      if @bot.inflight_active?(user_id)
        return @bot.send_message(user_id, 'Подожди, предыдущий запрос ещё выполняется.',
                                 @bot.chat_keyboard)
      end

      @bot.begin_inflight(user_id)

      worker_thread = Thread.new do
        Thread.current.report_on_exception = false
        chat(user_id, text)
      end

      # Service threads keep UX responsive while the model is generating.
      typing_thread = start_typing(user_id)
      notice_thread = start_thinking_notice(user_id)

      @bot.register_inflight_threads(
        user_id,
        worker_thread: worker_thread,
        typing_thread: typing_thread,
        notice_thread: notice_thread
      )
    end

    def chat(user_id, text)
      @bot.session.add_message('user', text)
      reply = +''

      # Stream tokens into a buffer to support cancellation at any point.
      @bot.hermes.chat_streaming(@bot.session.messages) do |token|
        raise 'cancelled' unless @bot.inflight_active?(user_id)

        reply << token
      end

      return unless @bot.inflight_active?(user_id)

      @bot.session.add_message('assistant', reply)
      @bot.send_message(user_id, @bot.strip_markdown(reply), @bot.chat_keyboard)
    rescue RuntimeError => e
      # Internal cancellation is expected and should not surface as an error.
      return if e.message == 'cancelled'

      raise
    rescue HermesClient::Error => e
      return unless @bot.inflight_active?(user_id)

      @bot.send_message(user_id, "Ошибка Hermes: #{e.message}", @bot.chat_keyboard)
    ensure
      # Always release in-flight state, no matter how the request ended.
      @bot.finish_inflight(user_id)
    end

    def start_typing(user_id)
      Thread.new do
        Thread.current.report_on_exception = false
        # Keep sending typing events while a request is active.
        loop do
          break unless @bot.inflight_active?(user_id)

          @bot.set_typing(user_id)
          sleep(8)
        end
      end
    end

    def start_thinking_notice(user_id)
      Thread.new do
        Thread.current.report_on_exception = false
        # Send a one-time hint only for long-running requests.
        sleep(90)
        next unless @bot.inflight_active?(user_id)
        next if @bot.inflight_notice_sent?(user_id)

        @bot.mark_inflight_notice_sent(user_id)
        @bot.send_message(user_id, 'Модель ещё думает. Можешь нажать «Остановить запрос» если хочешь.',
                          @bot.chat_keyboard)
      end
    end
  end
end
