# frozen_string_literal: true

module States
  class BaseState
    def initialize(bot)
      @bot = bot
    end

    def handle(user_id, text, payload)
      raise NotImplementedError, "#{self.class} must implement handle"
    end

    private

    # Switches active state and persists it for restart recovery.
    def transition_to(state_class, user_id)
      @bot.state = state_class.new(@bot)
      ChatSession.save_state(user_id, state_class.name.split('::').last.gsub('State', '').downcase, @bot.session&.id)
    end
  end
end
