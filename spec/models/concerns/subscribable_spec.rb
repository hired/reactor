require 'spec_helper'

class Auction < ActiveRecord::Base
  on_event :bid_made do |event|
    event.target.update_column :status, 'first_bid_made'
  end

  on_event :puppy_delivered, :ring_bell
  on_event :puppy_delivered, -> (event) { }
  on_event :any_event, -> (event) {  puppies! }
  on_event :pooped, :pick_up_poop, delay: 5.minutes
  on_event '*' do |event|
    event.actor.more_puppies! if event.name == 'another_event'
  end

  on_event :cat_delivered, in_memory: true do |event|
    puppies!
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
  let(:scheduled) { Sidekiq::ScheduledSet.new }

  describe 'on_event' do
    it 'binds block of code statically to event being fired' do
      Auction.any_instance.should_receive(:update_column).with(:status, 'first_bid_made')
      Reactor::Event.publish(:bid_made, target: Auction.create)
    end

    describe 'building uniquely named subscriber handler classes' do
      it 'adds a static subscriber to the global lookup constant' do
        expect(Reactor::SUBSCRIBERS['puppy_delivered'][0]).to eq(Reactor::StaticSubscribers::AuctionOnPuppyDeliveredCallsRingBell)
        expect(Reactor::SUBSCRIBERS['puppy_delivered'][1]).to eq(Reactor::StaticSubscribers::AuctionOnPuppyDeliveredCallsBlock0)
      end
    end

    describe 'binding symbol of class method' do
      it 'fires on event' do
        Auction.should_receive(:ring_bell)
        Reactor::Event.publish(:puppy_delivered)
      end

      it 'can be delayed' do
        Auction.should_receive(:pick_up_poop)
        Auction.should_receive(:delay_for).with(5.minutes).and_return(Auction)
        Reactor::Event.perform('pooped', {})
      end
    end

    it 'binds proc' do
      Auction.should_receive(:puppies!)
      Reactor::Event.publish(:any_event)
    end

    it 'accepts wildcard event name' do
      Auction.any_instance.should_receive(:more_puppies!)
      Reactor::Event.publish(:another_event, actor: Auction.create)
    end

    describe 'in_memory flag' do
      it 'doesnt fire perform_async when true' do
        Auction.should_receive(:puppies!)
        Reactor::StaticSubscribers::AuctionOnCatDeliveredCallsBlock0.should_not_receive(:perform_async)
        Reactor::Event.publish(:cat_delivered)
      end

      it 'fires perform_async when falsey' do
        Reactor::StaticSubscribers::AuctionOnWildcardCallsBlock0.should_receive(:perform_async)
        Reactor::Event.publish(:puppy_delivered)
      end
    end

    describe '#perform' do
      it 'returns :__perform_aborted__ when Reactor is in test mode' do
        Reactor::StaticSubscribers::TestModeAuctionOnTestPuppyDeliveredCallsBlock0.new.perform({}).should == :__perform_aborted__
        Reactor::Event.publish(:test_puppy_delivered)
      end

      it 'performs normally when specifically enabled' do
        Reactor.enable_test_mode_subscriber(TestModeAuction)
        Reactor::StaticSubscribers::TestModeAuctionOnTestPuppyDeliveredCallsBlock0.new.perform({}).should_not == :__perform_aborted__
        Reactor::Event.publish(:test_puppy_delivered)
      end
    end
  end
end
