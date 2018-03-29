# frozen_string_literal: true

require 'spec_helper'
require 'sidekiq/testing'

class Publisher < ApplicationRecord
  belongs_to :pet

  def ring_timeout
    start_at + 30.seconds
  end

  def ring_timeout_was
    previous_changes[:start_at][0] + 30.seconds
  end

  publishes :bell
  publishes :on_update, watch: :updated_at
  publishes :ring, at: :ring_timeout, watch: :start_at
  publishes :begin, at: :start_at, additional_info: 'curtis was here'
  publishes :conditional_event_on_save, at: :start_at, enqueue_if: -> { we_want_it }
  publishes :conditional_event_on_publish, at: :start_at, if: -> { we_want_it }
  publishes :woof, actor: :pet, target: :self
end

describe Reactor::Publishable do
  before { allow(Reactor::Event).to receive(:perform_at).and_call_original }

  describe 'publishes' do
    let(:pet) { Pet.create! }
    let(:publisher) { Publisher.create!(pet: pet, start_at: Time.current + 1.day, we_want_it: false) }

    it 'publishes an event with actor_id and actor_type set as self' do
      publisher
      expect(Reactor::Event).to receive(:publish).with(:an_event, what: 'the', actor: publisher)
      publisher.publish(:an_event, what: 'the')
    end

    it 'publishes an event with provided actor and target methods' do
      allow(Reactor::Event).to receive(:publish).exactly(6).times
      publisher
      expect(Reactor::Event).to have_received(:publish).with(:woof, a_hash_including(actor: pet, target: publisher))
    end

    it 'reschedules an event when the :at time changes' do
      start_at = publisher.start_at
      new_start_at = start_at + 1.week

      allow(Reactor::Event).to receive(:reschedule)

      publisher.start_at = new_start_at
      publisher.save!

      expect(Reactor::Event).to have_received(:reschedule).with(:begin,
                                                                a_hash_including(
                                                                  at: new_start_at,
                                                                  actor: publisher,
                                                                  was: start_at,
                                                                  additional_info: 'curtis was here'
                                                                ))
    end

    it 'reschedules an :at event when the :watch field changes' do
      ring_time = publisher.ring_timeout
      new_start_at = publisher.start_at + 1.week
      new_ring_time = new_start_at + 30.seconds

      allow(Reactor::Event).to receive(:reschedule)

      publisher.start_at = new_start_at
      publisher.save!

      expect(Reactor::Event).to have_received(:reschedule).with(:ring,
                                                                a_hash_including(
                                                                  at: new_ring_time,
                                                                  actor: publisher,
                                                                  was: ring_time
                                                                ))
    end

    it 'publishes an event when the :watch field changes' do
      publisher

      allow(Reactor::Event).to receive(:publish)

      publisher.update!(start_at: publisher.start_at + 1.week)

      expect(Reactor::Event).to have_received(:publish).with(:on_update,
                                                             a_hash_including(
                                                               actor: publisher
                                                             ))
    end

    it 'publishes an event when the :watch field changes' do
      publisher

      allow(Reactor::Event).to receive(:publish)

      publisher.update!(start_at: publisher.start_at + 1.week)

      expect(Reactor::Event).to have_received(:publish).with(:on_update,
                                                             a_hash_including(
                                                               actor: publisher
                                                             ))
    end

    context 'conditional firing at publish time' do
      before do
        Sidekiq::Testing.fake!
        Sidekiq::Worker.clear_all
        publisher
        job = Reactor::Event.jobs.detect do |job|
          job['class'] == 'Reactor::Event' && job['args'].first == 'conditional_event_on_publish'
        end
        @job_args = job['args']
      end

      after do
        Sidekiq::Testing.inline!
      end

      it 'calls the subscriber when if is set to true' do
        publisher.we_want_it = true
        publisher.start_at = 3.days.from_now
        allow(Reactor::Event).to receive(:perform_at)
        publisher.save!
        expect(Reactor::Event).to have_received(:perform_at).with(publisher.start_at, :conditional_event_on_publish, anything)

        Reactor::Event.perform(@job_args[0], @job_args[1])
      end

      it 'does not call the subscriber when if is set to false' do
        publisher.we_want_it = false
        publisher.start_at = 3.days.from_now
        publisher.save!

        expect { Reactor::Event.perform(@job_args[0], @job_args[1]) }.to_not change { Sidekiq::Queues.jobs_by_queue.values.flatten.count }
      end

      it 'keeps the if intact when rescheduling' do
        old_start_at = publisher.start_at
        publisher.start_at = 3.days.from_now
        allow(Reactor::Event).to receive(:publish)
        expect(Reactor::Event).to receive(:publish).with(:conditional_event_on_publish,
                                                         at: publisher.start_at,
                                                         actor: publisher,
                                                         target: nil,
                                                         was: old_start_at,
                                                         if: anything)
        publisher.save!
      end

      it 'keeps the if intact when scheduling' do
        start_at = 3.days.from_now
        allow(Reactor::Event).to receive(:publish)
        expect(Reactor::Event).to receive(:publish).with(:conditional_event_on_publish,
                                                         at: start_at,
                                                         actor: anything,
                                                         target: nil,
                                                         if: anything)
        Publisher.create!(start_at: start_at)
      end
    end

    context 'conditional firing on save' do
      before do
        Sidekiq::Testing.fake!
        Sidekiq::Worker.clear_all
        publisher
        job = Reactor::Event.jobs.detect do |job|
          job['class'] == 'Reactor::Event' && job['args'].first == 'conditional_event_on_save'
        end
        @job_args = job ? job['args'] : []
      end

      after do
        Sidekiq::Testing.inline!
      end

      it 'does not call the subscriber when if is set to false' do
        old_start_at = publisher.start_at
        publisher.we_want_it = false
        publisher.start_at = 3.days.from_now
        allow(Reactor::Event).to receive(:publish)
        expect(Reactor::Event).to_not receive(:reschedule).with(:conditional_event_on_save)
        expect(Reactor::Event).to_not receive(:publish).with(:conditional_event_on_save)
        publisher.save!
      end

      it 'does rescheduling' do
        old_start_at = publisher.start_at
        publisher.we_want_it = true
        publisher.start_at = 3.days.from_now
        allow(Reactor::Event).to receive(:publish)
        expect(Reactor::Event).to receive(:publish).with(:conditional_event_on_save,
                                                         at: publisher.start_at,
                                                         actor: publisher,
                                                         target: nil,
                                                         was: old_start_at)
        publisher.save!
      end

      it 'does conditional scheduling scheduling' do
        start_at = 3.days.from_now
        allow(Reactor::Event).to receive(:publish)
        expect(Reactor::Event).to receive(:publish).with(:conditional_event_on_save,
                                                         at: start_at,
                                                         actor: anything,
                                                         target: nil)
        Publisher.create!(start_at: start_at, we_want_it: true)
      end
    end

    it 'supports immediate events (on create) that get fired once' do
      allow(Reactor::Event).to receive(:perform_async)
      expect(Reactor::Event).to receive(:perform_async)
        .with(:woof, hash_including(actor_type: 'Pet'))
      expect(Reactor::Event).to receive(:perform_async)
        .with(:bell, hash_including(actor_type: 'Publisher'))

      publisher

      # and dont get fired on update
      publisher.start_at = 1.day.from_now
      expect(Reactor::Event).to_not receive(:perform_async).with(:bell)
      expect(Reactor::Event).to_not receive(:perform_async).with(:woof)
      publisher.save
    end

    it 'supports immediate events (on watch)' do
      allow(Reactor::Event).to receive(:perform_async)

      expect(Reactor::Event).to receive(:perform_async)
        .with(:on_update, hash_including(actor_type: 'Publisher')).twice

      publisher
      publisher.update!(start_at: 1.day.from_now)
    end

    it 'supports immediate events (on watch)' do
      allow(Reactor::Event).to receive(:perform_async)

      expect(Reactor::Event).to receive(:perform_async)
        .with(:on_update, hash_including(actor_type: 'Publisher')).twice

      publisher
      publisher.update!(start_at: 1.day.from_now)
    end

    it 'does publish an event scheduled for the future' do
      future = Time.now.utc + 1.week

      expect(Reactor::Event).to receive(:perform_at)
        .with(future, :begin, hash_including('additional_info' => 'curtis was here'))

      Publisher.create!(pet: pet, start_at: future)
    end
  end
end
