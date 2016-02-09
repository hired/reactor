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
    "ring ring! #{event}"
  end

  def self.pick_up_poop(event); end
end

Reactor.in_test_mode do
  class TestModeAuction
    include Reactor::Subscribable

    on_event :test_puppy_delivered, -> (event) { "success" }
    on_event :test_normal_delay, :do_normal_thing, delay: 5.minutes

    def self.do_normal_thing(event); end
  end

  class TestWorker
    include Sidekiq::Worker
    include Reactor::Subscribable

    on_event :test_sidekiq_delay, :do_sidekiq_thing, delay: 5.minutes

    def self.do_sidekiq_thing(event); end
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
        expect(Reactor::SUBSCRIBERS['puppy_delivered'][0]).to eq(Reactor::StaticSubscribers::PuppyDeliveredHandler0)
        expect(Reactor::SUBSCRIBERS['puppy_delivered'][1]).to eq(Reactor::StaticSubscribers::PuppyDeliveredHandler1)
      end
    end

    describe 'binding symbol of class method' do
      it 'fires on event' do
        expect(Auction).to receive(:ring_bell)
        Reactor::Event.publish(:puppy_delivered)
      end

      it 'can be delayed' do
        expect(Auction).to receive(:pick_up_poop)
        expect(Auction).to receive(:delay_for).with(5.minutes).and_return(Auction)
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
        expect(Reactor::StaticSubscribers::CatDeliveredHandler0).not_to receive(:perform_async)
        Reactor::Event.publish(:cat_delivered)
      end

      it 'fires perform_async when falsey' do
        expect(Reactor::StaticSubscribers::WildcardHandler0).to receive(:perform_async)
        Reactor::Event.publish(:puppy_delivered)
      end
    end

    describe 'sidekiq perform definition hack' do
      subject { klass.instance_methods }

      context 'when not a sidekiq worker' do
        let(:klass) { TestModeAuction }
        it { is_expected.not_to include(:perform) }
      end

      context 'when a sidekiq worker' do
        let(:klass) { TestWorker }
        it { is_expected.to include(:perform) }
      end
    end

    describe '#perform' do
      subject(:perform) { handler.perform({actor_id: 55}) }
      let(:handler) { Reactor::StaticSubscribers::TestPuppyDeliveredHandler0.new }
      let(:source) { handler.source }

      context 'when test mode is not enabled' do
        it { is_expected.to eq(:__perform_aborted__) }
      end

      context 'when test mode is enabled' do
        before { Reactor.enable_test_mode_subscriber(TestModeAuction) }

        it { is_expected.not_to eq(:__perform_aborted__) }

        describe 'delays' do
          context 'when not a sidekiq worker' do
            let(:handler) { Reactor::StaticSubscribers::TestNormalDelayHandler0.new }

            it 'calls delay_for on source' do
              expect(source).to receive(:delay_for).and_call_original
              expect(source).not_to receive(:perform_in)
              perform
            end
          end

          context 'when a sidekiq worker' do
            before { Reactor.enable_test_mode_subscriber(TestWorker) }
            let(:handler) { Reactor::StaticSubscribers::TestSidekiqDelayHandler0.new }

            it 'calls perform_in instead of delay_for' do
              expect(source).to receive(:perform_in).and_call_original
              expect(source).not_to receive(:delay_for)
              perform
            end

            it 'calls perform on the source with method and data args' do
              expect_any_instance_of(TestWorker).to receive(:perform).with('do_sidekiq_thing', {'actor_id' => 55})
              perform
            end

            it 'calls a class method specified by symbol with event' do
              expect(TestWorker).to receive(:do_sidekiq_thing).with(Reactor::Event)
              perform
            end
          end
        end
      end
    end
  end
end
