# frozen_string_literal: true

require 'fileutils'
require 'spec_helper'
require_relative '../lib/bot'

RSpec.describe Bot do
  let(:hermes) { instance_double(HermesClient) }
  let(:bot) { Bot.new(vk_token: 'tok', vk_group_id: '1', hermes_client: hermes) }

  before do
    ChatSession.db_path = 'test_bot.db'
    ChatSession.setup_db
    stub_request(:any, /api\.vk\.com/).to_return(
      status: 200, body: JSON.dump({ response: 1 })
    )
  end

  after do
    FileUtils.rm_f('test_bot.db')
    ChatSession.instance_variable_set(:@db_path, nil)
  end

  def handle(text: '', payload: nil)
    bot.state.handle(1, text, payload)
  end

  context 'in :idle state' do
    it 'starts new session on new_session cmd' do
      handle(payload: { 'cmd' => 'new_session' })
      expect(bot.state).to be_a(States::ChattingState)
      expect(bot.instance_variable_get(:@session)).not_to be_nil
    end

    it 'transitions to selecting_session when sessions exist' do
      ChatSession.create('Old session')
      handle(payload: { 'cmd' => 'my_sessions' })
      expect(bot.state).to be_a(States::SelectingSessionState)
    end

    it 'shows main menu when no sessions exist' do
      handle(payload: { 'cmd' => 'my_sessions' })
      expect(bot.state).to be_a(States::IdleState)
    end

    it 'shows status' do
      allow(hermes).to receive(:healthy?).and_return(true)
      handle(payload: { 'cmd' => 'status' })
      expect(WebMock).to have_requested(:get, /messages.send/)
        .with(query: hash_including('message' => 'Hermes онлайн.'))
    end
  end

  context 'in :chatting state' do
    before do
      handle(payload: { 'cmd' => 'new_session' })
      allow(hermes).to receive(:chat).and_return('Agent reply')
      stub_request(:get, /messages.setActivity/).to_return(status: 200, body: '{}')
    end

    it 'sends message to hermes and saves history' do
      handle(text: 'Hello')
      session = bot.instance_variable_get(:@session)
      expect(session.messages.length).to eq(2)
    end

    it 'handles stop_request command' do
      handle(payload: { 'cmd' => 'stop_request' })
      expect(WebMock).to(have_requested(:get, /messages.send/)
        .with { |req| CGI.unescape(req.uri.query).include?('Выполнение остановлено') })
    end

    it 'transitions to confirming_clear on clear_history' do
      handle(payload: { 'cmd' => 'clear_history' })
      expect(bot.state).to be_a(States::ConfirmingClearState)
    end

    it 'returns to idle on main_menu' do
      handle(payload: { 'cmd' => 'main_menu' })
      expect(bot.state).to be_a(States::IdleState)
    end

    it 'handles empty message gracefully' do
      handle(text: '')
      session = bot.instance_variable_get(:@session)
      expect(session.messages).to be_empty
    end

    it 'handles HermesClient::Error gracefully' do
      allow(hermes).to receive(:chat).and_raise(HermesClient::Error, '500')
      expect { handle(text: 'Hi') }.not_to raise_error
    end
  end

  context 'in :confirming_clear state' do
    before do
      handle(payload: { 'cmd' => 'new_session' })
      allow(hermes).to receive(:chat).and_return('reply')
      stub_request(:get, /messages.setActivity/).to_return(status: 200, body: '{}')
      handle(text: 'Hello')
      handle(payload: { 'cmd' => 'clear_history' })
    end

    it 'clears history on confirm_yes' do
      handle(payload: { 'cmd' => 'confirm_yes' })
      session = bot.instance_variable_get(:@session)
      expect(session.messages).to be_empty
      expect(bot.state).to be_a(States::ChattingState)
    end

    it 'keeps history on confirm_no' do
      handle(payload: { 'cmd' => 'confirm_no' })
      session = bot.instance_variable_get(:@session)
      expect(session.messages).not_to be_empty
      expect(bot.state).to be_a(States::ChattingState)
    end
  end

  context 'in :selecting_session state' do
    let!(:old_session) { ChatSession.create('Old') }

    before do
      handle(payload: { 'cmd' => 'my_sessions' })
    end

    it 'loads selected session' do
      handle(payload: { 'cmd' => 'select_session', 'id' => old_session.id })
      expect(bot.state).to be_a(States::ChattingState)
      expect(bot.instance_variable_get(:@session).name).to eq('Old')
    end

    it 'returns to idle on main_menu' do
      handle(payload: { 'cmd' => 'main_menu' })
      expect(bot.state).to be_a(States::IdleState)
    end
  end
end
