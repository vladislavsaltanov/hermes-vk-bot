require_relative 'hermes_client'
require_relative 'chat_session'

class Bot
  def initialize(vk_token:, vk_group_id:, hermes_client:)
    @token = vk_token
    @group_id = vk_group_id
    @hermes = hermes_client
    @state = :idle
    @session = nil
  end

  def handle(user_id:, text:, payload:)
  end
end
