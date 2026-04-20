# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/hermes_client'
require 'dotenv/load'

RSpec.describe HermesClient do
  let(:hermes_url) { ENV.fetch('HERMES_URL', nil) }
  let(:client) { HermesClient.new(base_url: hermes_url, api_key: 'key') }

  describe '#chat' do
    it 'returns assistant content' do
      stub_request(:post, "#{hermes_url}/v1/chat/completions")
        .to_return(status: 200, body: JSON.dump({
                                                  choices: [{ message: { content: 'Hello!' } }]
                                                }))

      expect(client.chat([{ role: 'user', content: 'Hi' }])).to eq('Hello!')
    end

    it 'raises Error on non-200' do
      stub_request(:post, "#{hermes_url}/v1/chat/completions").to_return(status: 500)
      expect { client.chat([]) }.to raise_error(HermesClient::Error, 'HTTP 500')
    end

    it 'raises Error on empty response' do
      stub_request(:post, "#{hermes_url}/v1/chat/completions")
        .to_return(status: 200, body: JSON.dump({ choices: [{ message: { content: nil } }] }))
      expect { client.chat([]) }.to raise_error(HermesClient::Error, 'Empty response')
    end
  end

  describe '#healthy?' do
    it 'returns true on 200' do
      stub_request(:get, "#{hermes_url}/health").to_return(status: 200)
      expect(client.healthy?).to be true
    end

    it 'returns false on connection error' do
      stub_request(:get, "#{hermes_url}/health").to_raise(Faraday::ConnectionFailed.new('err'))
      expect(client.healthy?).to be false
    end
  end
end
