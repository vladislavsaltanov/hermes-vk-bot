# frozen_string_literal: true

require 'fileutils'
require_relative '../lib/chat_session'

RSpec.describe ChatSession do
  before(:each) do
    ChatSession.db_path = 'test_bot.db'
    ChatSession.setup_db
  end

  after(:each) do
    FileUtils.rm_f('test_bot.db')
    ChatSession.instance_variable_set(:@db_path, nil)
  end

  describe '.create' do
    it 'creates session with given name' do
      session = ChatSession.create('Test')
      expect(session.id).not_to be_nil
      expect(session.name).to eq('Test')
    end
  end

  describe '.all' do
    it 'returns all sessions newest first' do
      ChatSession.create('A')
      sleep(1)
      ChatSession.create('B')
      expect(ChatSession.all.map(&:name)).to eq(%w[B A])
    end
  end

  describe '.find' do
    it 'finds session by id' do
      session = ChatSession.create('Test')
      expect(ChatSession.find(session.id).name).to eq('Test')
    end

    it 'returns nil for unknown id' do
      expect(ChatSession.find(999)).to be_nil
    end
  end

  describe '#messages' do
    it 'returns messages in order' do
      session = ChatSession.create('Test')
      session.add_message('user', 'Hello')
      session.add_message('assistant', 'Hi!')
      expect(session.messages).to eq([
                                       { role: 'user', content: 'Hello' },
                                       { role: 'assistant', content: 'Hi!' }
                                     ])
    end
  end

  describe '#clear_messages' do
    it 'deletes all messages in session' do
      session = ChatSession.create('Test')
      session.add_message('user', 'Hello')
      session.clear_messages
      expect(session.messages).to be_empty
    end
  end
end
