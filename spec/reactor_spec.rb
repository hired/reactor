require 'spec_helper'

Reactor.in_test_mode do
  class SomeClass
    include Reactor::Subscribable
    on_event :test_event, -> (event) { self.spy_on_me }
  end
end

describe Reactor do
  let(:subscriber) { SomeClass }

  describe '.test_mode!' do
    before { Reactor.disable_test_mode! }

    it 'sets Reactor into test mode' do
      expect(Reactor.test_mode?).to be_falsey
      Reactor.test_mode!
      expect(Reactor.test_mode?).to be_truthy
    end
  end

  context 'in test mode' do
    before { Reactor.test_mode! }
    after  { Reactor.disable_test_mode! }

    it 'subscribers created in test mode are disabled' do
      expect(subscriber).not_to receive :spy_on_me
      Reactor::Event.publish :test_event
    end

    describe '.with_subscriber_enabled' do
      it 'enables a subscriber during test mode' do
        expect(subscriber).to receive :spy_on_me
        Reactor.with_subscriber_enabled(subscriber) do
          Reactor::Event.publish :test_event
        end
      end

      it 'disables the subscriber outside the block' do
        expect(Reactor::TEST_MODE_SUBSCRIBERS).to be_empty
        Reactor.with_subscriber_enabled(subscriber) do
          expect(Reactor::TEST_MODE_SUBSCRIBERS).to contain_exactly(subscriber)
        end
        expect(Reactor::TEST_MODE_SUBSCRIBERS).to be_empty
      end

      it 'correctly handles exceptions inside the block' do
        expect(Reactor::TEST_MODE_SUBSCRIBERS).to be_empty
        expect {
          Reactor.with_subscriber_enabled(subscriber) do
            raise RuntimeError
          end
        }.to raise_error(RuntimeError)
        expect(Reactor::TEST_MODE_SUBSCRIBERS).to be_empty
      end
    end

    describe '.with_subscriber_disabled' do
      before { Reactor.enable_test_mode_subscriber(subscriber) }

      it 'disables a subscriber during test mode' do
        expect(subscriber).not_to receive :spy_on_me
        Reactor.with_subscriber_disabled(subscriber) do
          Reactor::Event.publish :test_event
        end
      end

      it 'enables the subscriber outside the block' do
        expect(Reactor::TEST_MODE_SUBSCRIBERS).to contain_exactly(subscriber)
        Reactor.with_subscriber_disabled(subscriber) do
          expect(Reactor::TEST_MODE_SUBSCRIBERS).to be_empty
        end
        expect(Reactor::TEST_MODE_SUBSCRIBERS).to contain_exactly(subscriber)
      end

      it 'correctly handles exceptions inside the block' do
        expect(Reactor::TEST_MODE_SUBSCRIBERS).to contain_exactly(subscriber)
        expect {
          Reactor.with_subscriber_disabled(subscriber) do
            raise RuntimeError
          end
        }.to raise_error(RuntimeError)
        expect(Reactor::TEST_MODE_SUBSCRIBERS).to contain_exactly(subscriber)
      end
    end
  end
end
