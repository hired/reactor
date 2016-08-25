require 'spec_helper'

class Auction < ActiveRecord::Base
  on_event :bid_made do |event|
    event.target.update_column :status, 'first_bid_made'
  end

  on_event :puppy_delivered, :ring_bell
  on_event :puppy_delivered, handler_name: :do_nothing_handler do |event|

  end
  on_event :any_event, -> (event) {  puppies! }
  on_event :pooped, :pick_up_poop, delay: 5.minutes
  on_event '*' do |event|
    event.actor.more_puppies! if event.name == 'another_event'
  end

  on_event :cat_delivered, in_memory: true do |event|
    puppies!
  end

  def self.ring_bell(event)
    "ring ring! #{event}"
  end
end

module MyNamespace
  class MyClass
    include Reactor::Subscribable
    on_event :rain, :umbrella
  end

  def self.umbrella
    puts 'get an umbrella'
  end
end

Reactor.in_test_mode do
  class TestModeAuction < ActiveRecord::Base
    on_event :test_puppy_delivered, -> (event) { "success" }
  end
end

describe Reactor::Subscribable do
  let(:scheduled) { Sidekiq::ScheduledSet.new }
  before { Reactor::TEST_MODE_SUBSCRIBERS.clear }

  describe 'on_event' do
    it 'binds block of code statically to event being fired' do
      expect_any_instance_of(Auction).to receive(:update_column).with(:status, 'first_bid_made')
      Reactor::Event.publish(:bid_made, target: Auction.create!(start_at: 10.minutes.from_now))
    end

    describe 'building uniquely named subscriber handler classes' do
      it 'adds a static subscriber to the global lookup constant' do
        expect(Reactor::SUBSCRIBERS['puppy_delivered'][0]).to eq(Reactor::StaticSubscribers::Auction::PuppyDeliveredHandler)
        expect(Reactor::SUBSCRIBERS['puppy_delivered'][1]).to eq(Reactor::StaticSubscribers::Auction::DoNothingHandler)
      end

      it 'adds a static subscriber for namespaced classes' do
        expect(Reactor::SUBSCRIBERS['rain'][0]).to eq(Reactor::StaticSubscribers::MyClass::RainHandler)
      end
    end

    describe 'binding symbol of class method' do
      it 'fires on event' do
        expect(Auction).to receive(:ring_bell)
        Reactor::Event.publish(:puppy_delivered)
      end

      it 'can be delayed' do
        expect(Auction).to receive(:pick_up_poop)
        expect(Auction).to receive(:perform_in).with(5.minutes).and_return(Auction)
        Reactor::Event.perform('pooped', {})
      end
    end

    it 'binds proc' do
      expect(Auction).to receive(:puppies!)
      Reactor::Event.publish(:any_event)
    end

    it 'accepts wildcard event name' do
      expect_any_instance_of(Auction).to receive(:more_puppies!)
      Reactor::Event.publish(:another_event, actor: Auction.create!(start_at: 5.minutes.from_now))
    end

    describe 'in_memory flag' do
      it 'doesnt fire perform_async when true' do
        expect(Auction).to receive(:puppies!)
        expect(Reactor::StaticSubscribers::Auction::CatDeliveredHandler).not_to receive(:perform_async)
        Reactor::Event.publish(:cat_delivered)
      end

      it 'fires perform_async when falsey' do
        expect(Reactor::StaticSubscribers::Auction::WildcardHandler).to receive(:perform_async)
        Reactor::Event.publish(:puppy_delivered)
      end
    end

    describe '#perform' do
      it 'returns :__perform_aborted__ when Reactor is in test mode' do
        expect(Reactor::StaticSubscribers::TestModeAuction::TestPuppyDeliveredHandler.new.perform({})).to eq(:__perform_aborted__)
        Reactor::Event.publish(:test_puppy_delivered)
      end

      it 'performs normally when specifically enabled' do
        Reactor.enable_test_mode_subscriber(TestModeAuction)
        expect(Reactor::StaticSubscribers::TestModeAuction::TestPuppyDeliveredHandler.new.perform({})).not_to eq(:__perform_aborted__)
        Reactor::Event.publish(:test_puppy_delivered)
      end
    end
  end
end
