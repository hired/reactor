require 'spec_helper'

class TestEventSubscriber
  include Reactor::Subscribable
  on_event :test_event do
    # noop
  end
end

class OtherTestEventSubscriber
  include Reactor::Subscribable
  on_event :other_test_event do
    # noop
  end
end


describe Reactor do
  let(:subscriber) do
    Reactor.in_test_mode do
      Class.new(ActiveRecord::Base) do
        on_event :test_event, -> (event) { self.spy_on_me }
      end
    end
  end

  describe '.test_mode!' do
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
    end
  end

  context 'in test mode' do

    before { Reactor.test_mode! }

    context 'with stubbed subscriber' do

      before do
        Reactor::Event.publish(:test_event, param1: 'one', param2: 'two')
        Reactor::Event.publish(:other_test_event, param3: 'three', param4: 'four')
      end

      it 'records test events' do
        expect(Reactor.test_event).to_not be_nil
      end

      it 'finds test events by name' do
        expect(Reactor.test_event(:test_event)).to_not be_nil
        expect(Reactor.test_event(:other_test_event)).to_not be_nil
      end

      it 'finds test events by name and value' do
        Reactor::Event.publish(:test_event, param5: 'five', param6: 'six')
        expect(Reactor.test_event(:test_event, param1: 'one')[:param1]).to eq('one')
      end

      it 'finds all test events' do
        expect(Reactor.test_events).to be_an(Array)
        expect(Reactor.test_events.first[:param1]).to eq('one')
        expect(Reactor.test_events.last[:param3]).to  eq('three')
      end

      it 'finds all test events matching name' do
        Reactor::Event.publish(:test_event, param5: 'five', param6: 'six')
        expect(Reactor.test_events(:test_event).count).to eq(2)
      end

      it 'finds all test events by name and value' do
        Reactor::Event.publish(:test_event, param5: 'five', param6: 'six')
        Reactor::Event.publish(:test_event, param1: 'one', param7: 'seven')
        events = Reactor.test_events(:test_event, param1: 'one')
        expect(events.count).to eq(2)
        expect(events.first[:param2]).to eq('two')
        expect(events.last[:param7]).to eq('seven')
      end
    end
  end
end
