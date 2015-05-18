require 'spec_helper'

class Auction < ActiveRecord::Base
  include GlobalID::Identification

  on_event :bid_made do |event|
    event.target.update_column :status, 'first_bid_made'
  end

  on_event :puppy_delivered, :ring_bell
  on_event :puppy_delivered, -> (event) { }
  on_event :any_event, -> (event) {  puppies! }
  on_event '*' do |event|
    event.actor.more_puppies!(event.time) if event.name == 'another_event'
  end

  def self.ring_bell(event)
    pp "ring ring! #{event}"
  end
end

Reactor.in_test_mode do
  class TestModeAuction < ActiveRecord::Base
    on_event :test_puppy_delivered, -> (event) { pp "success" }
  end
end

describe Reactor::Subscribable do
  before { Reactor::TEST_MODE_SUBSCRIBERS.clear }

  describe 'on_event' do
    it 'binds block of code statically to event being fired' do
      expect_any_instance_of(Auction).to receive(:update_column).with(:status, 'first_bid_made')
      Reactor::Event.publish(:bid_made, target: Auction.create!(start_at: 10.minutes.from_now))
    end

    describe 'building uniquely named subscriber handler classes' do
      it 'adds a static subscriber to the global lookup constant' do
        expect(Reactor::SUBSCRIBERS['puppy_delivered'][0]).to eq(Reactor::StaticSubscribers::PuppyDeliveredHandler0)
        expect(Reactor::SUBSCRIBERS['puppy_delivered'][1]).to eq(Reactor::StaticSubscribers::PuppyDeliveredHandler1)
      end
    end

    it 'binds symbol of class method' do
      expect(Auction).to receive(:ring_bell)
      Reactor::Event.publish(:puppy_delivered)
    end

    it 'binds proc' do
      expect(Auction).to receive(:puppies!)
      Reactor::Event.publish(:any_event)
    end

    it 'accepts wildcard event name' do
      expect_any_instance_of(Auction).to receive(:more_puppies!)
      Reactor::Event.publish(:another_event, actor: Auction.create!(start_at: 5.minutes.from_now))
    end

    describe 'time deserialization' do
      it 'accepts wildcard event name' do
        now = Time.current
        expect_any_instance_of(Auction).to receive(:more_puppies!) do |instance, time|
          expect(time).to be_within(1.second).of(now)
        end
        Reactor::Event.publish(:another_event, actor: Auction.create!(start_at: 5.minutes.from_now), time: now)
      end
    end

    describe '#perform' do
      it 'returns :__perform_aborted__ when Reactor is in test mode' do
        expect(Reactor::StaticSubscribers::TestPuppyDeliveredHandler0.new.perform({})).to eq(:__perform_aborted__)
        Reactor::Event.publish(:test_puppy_delivered)
      end

      it 'performs normally when specifically enabled' do
        Reactor.enable_test_mode_subscriber(TestModeAuction)
        expect(Reactor::StaticSubscribers::TestPuppyDeliveredHandler0.new.perform({})).not_to eq(:__perform_aborted__)
        Reactor::Event.publish(:test_puppy_delivered)
      end
    end
  end
end
