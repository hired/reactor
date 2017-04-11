require 'spec_helper'
require 'sidekiq/testing'

class Auction < ActiveRecord::Base
  belongs_to :pet

  def ring_timeout
    start_at + 30.seconds
  end

  def ring_timeout_was
    previous_changes[:start_at][0] + 30.seconds
  end

  publishes :bell
  publishes :ring, at: :ring_timeout, watch: :start_at
  publishes :begin, at: :start_at, additional_info: 'curtis was here'
  publishes :conditional_event_on_save, at: :start_at, if: -> { we_want_it }
  publishes :woof, actor: :pet, target: :self
end

class TestSubscriber < Reactor::Subscriber
  @@called = false

  on_fire do
    @@called = true
  end
end

describe Reactor::Publishable do
  before do
    TestSubscriber.destroy_all
    TestSubscriber.class_variable_set(:@@called, false)
  end

  describe 'publish' do
    let(:pet) { Pet.create! }
    let(:auction) { Auction.create!(pet: pet, start_at: Time.current + 1.day, we_want_it: false) }

    it 'publishes an event with actor_id and actor_type set as self' do
      auction
      expect(Reactor::Event).to receive(:publish).with(:an_event, what: 'the', actor: auction)
      auction.publish(:an_event, {what: 'the'})
    end

    it 'publishes an event with provided actor and target methods' do
      allow(Reactor::Event).to receive(:publish).exactly(5).times
      auction
      expect(Reactor::Event).to have_received(:publish).with(:woof, a_hash_including(actor: pet, target: auction))
    end

    it 'reschedules an event when the :at time changes' do
      start_at = auction.start_at
      new_start_at = start_at + 1.week

      allow(Reactor::Event).to receive(:reschedule)

      auction.start_at = new_start_at
      auction.save!

      expect(Reactor::Event).to have_received(:reschedule).with(:begin,
        a_hash_including(
          at: new_start_at,
          actor: auction,
          was: start_at,
          additional_info: 'curtis was here'
        )
      )
    end

    it 'reschedules an event when the :watch field changes' do
      ring_time = auction.ring_timeout
      new_start_at = auction.start_at + 1.week
      new_ring_time = new_start_at + 30.seconds

      allow(Reactor::Event).to receive(:reschedule)

      auction.start_at = new_start_at
      auction.save!

      expect(Reactor::Event).to have_received(:reschedule).with(:ring,
        a_hash_including(
          at: new_ring_time,
          actor: auction,
          was: ring_time
        )
      )
    end

    context 'conditional firing' do
      let(:subscriber_worker) { Reactor::Subscriber::SubscriberWorker }

      before do
        Sidekiq::Testing.fake!
        Sidekiq::Worker.clear_all
        TestSubscriber.create! event_name: :conditional_event_on_save
        auction
        job = Reactor::Event.jobs.detect do |job|
          job['class'] == 'Reactor::Event' && job['args'].first == 'conditional_event_on_save'
        end
        @job_args = job['args']
      end

      after do
        Sidekiq::Testing.inline!
      end

      it 'calls the subscriber when if is set to true' do
        auction.we_want_it = true
        auction.start_at = 3.day.from_now
        auction.save!

        expect{ Reactor::Event.perform(@job_args[0], @job_args[1]) }.to change {
          subscriber_worker.jobs.count
        }.by(1)
      end

      it 'does not call the subscriber when if is set to false' do
        auction.we_want_it = false
        auction.start_at = 3.days.from_now
        auction.save!

        expect{ Reactor::Event.perform(@job_args[0], @job_args[1]) }.to_not change{ Sidekiq::Extensions::DelayedClass.jobs.size }
      end

      it 'keeps the if intact when rescheduling' do
        old_start_at = auction.start_at
        auction.start_at = 3.day.from_now
        allow(Reactor::Event).to receive(:publish)
        expect(Reactor::Event).to receive(:publish).with(:conditional_event_on_save, {
          at: auction.start_at,
          actor: auction,
          target: nil,
          was: old_start_at,
          if: anything
        })
        auction.save!
      end

      it 'keeps the if intact when scheduling' do
        start_at = 3.days.from_now
        allow(Reactor::Event).to receive(:publish)
        expect(Reactor::Event).to receive(:publish).with(:conditional_event_on_save, {
          at: start_at,
          actor: anything,
          target: nil,
          if: anything
        })
        Auction.create!(start_at: start_at)
      end
    end

    it 'supports immediate events (on create) that get fired once' do
      TestSubscriber.create! event_name: :bell
      auction
      expect(TestSubscriber.class_variable_get(:@@called)).to be_truthy
      TestSubscriber.class_variable_set(:@@called, false)
      auction.start_at = 1.day.from_now
      auction.save
      expect(TestSubscriber.class_variable_get(:@@called)).to be_falsey
    end

    it 'does publish an event scheduled for the future' do
      TestSubscriber.create! event_name: :begin
      Auction.create!(pet: pet, start_at: Time.current + 1.week)

      expect(TestSubscriber.class_variable_get(:@@called)).to be_truthy
    end
  end
end
