require 'spec_helper'

module MyModule
  class Pet < ActiveRecord::Base
  end

  class Cat < Pet
  end
end

class ArbitraryModel < ApplicationRecord

  on_event :barfed, handler_name: :bad do
    raise 'UNEXPECTED!'
  end

  on_event :barfed do
    'that was gross'
  end

end

class OtherWorker
  include Sidekiq::Worker
end

describe Reactor::Event do
  before { stub_reactor_subscribers }

  let(:model) { ArbitraryModel.create! }
  let(:event_name) { :user_did_this }

  describe 'encoding' do
    let(:event) { Reactor::Event.new(thing_one: "\xAD", thing_two: "\xAB", money: "£900", emoji: "\u{1f4a9}") }

    it 'strips bad characters' do
      expect(event.thing_one).to eq('')
      expect(event.thing_two).to eq('')
    end

    it 'allows valid multibyte UTF8' do
      expect(event.money).to eq('£900')
    end

    it 'allows astral plane characters' do
      expect(event.emoji).to eq("\u{1f4a9}")
    end
  end

  describe 'publish' do
    let!(:uuid) { 'uuid' }
    before { allow(SecureRandom).to receive(:uuid).and_return(uuid) }


    it 'fires the first perform and sets message event_id' do
      expect(Reactor::Event).to receive(:perform_async).with(event_name, 'actor_id' => '1', 'event' => :user_did_this, 'uuid' => uuid)
      Reactor::Event.publish(:user_did_this, actor_id: '1')
    end

    it 'generates and assigns a UUID to the event' do
      expect(Reactor::Event).to receive(:perform_async).with(event_name, 'actor_id' => '1', 'event' => :user_did_this, 'uuid' => uuid)
      Reactor::Event.publish(:user_did_this, actor_id: '1')
    end

    context 'when in a production rails console' do
      it 'requires a second argument srsly: true' do
        stub_const('Rails::Console', Class.new)
        ENV['RACK_ENV'] = 'production'

        expect {
          Reactor::Event.publish(:thing)
        }.to raise_exception(ArgumentError)

        expect {
          Reactor::Event.publish(:thing, srsly: true)
        }.to_not raise_exception

        ENV['RACK_ENV'] = 'development'
      end
    end
  end

  describe 'perform' do
    let(:event_name) { :barfed }

    it 'fires all subscribers' do
      expect(Reactor::StaticSubscribers::ArbitraryModel::BarfedHandler).
          to receive(:perform_where_needed).with(hash_including(actor_id: model.id.to_s))

      Reactor::Event.perform(event_name, actor_id: model.id.to_s, actor_type: model.class.to_s)
    end

    it 'sets a fired_at key in event data' do
      expect(Reactor::StaticSubscribers::ArbitraryModel::BarfedHandler).
          to receive(:perform_where_needed).with(hash_including(fired_at: a_kind_of(Time)))

      Reactor::Event.perform(event_name, actor_id: model.id.to_s, actor_type: model.class.to_s)
    end

    describe 'when subscriber throws exception', :sidekiq do
      it 'doesnt matter because it runs in a separate worker process' do
        expect {
          Reactor::Event.perform(
              event_name,
              somethin: 'up',
              actor_id: model.id.to_s,
              actor_type: model.class.to_s
          )
        }.to_not raise_exception
      end
    end
  end

  describe 'reschedule', :sidekiq do
    let(:scheduled) { Sidekiq::ScheduledSet.new }
    let(:time) { 1.hour.from_now }

    before do
      Sidekiq::Worker.clear_all
    end

    it 'can schedule and reschedule an event in the future' do
      expect {
        jid = Reactor::Event.publish :turtle_time, at: time
        expect(scheduled.find_job(jid).score).to eq(time.to_f)
      }.to change { scheduled.size }.by(1)

      expect {
        jid = Reactor::Event.reschedule :turtle_time, at: (time + 2.hours), was: time
        expect(scheduled.find_job(jid).score).to eq((time + 2.hours).to_f)
      }.to_not change { scheduled.size }
    end

    it 'will schedule an event in the future even if that event was not previously scheduled in the past' do
      expect {
        jid = Reactor::Event.reschedule :no_old_turtle_time, at: (time + 2.hours), was: time
        expect(scheduled.find_job(jid).score).to eq((time + 2.hours).to_f)
      }.to change{ scheduled.size }.by(1)
    end

    it 'will not schedule an event when the time passed in is nil' do
      expect {
        Reactor::Event.reschedule :no_old_turtle_time, at: nil, was: time
      }.to_not change{ scheduled.size }
    end

    context 'when an actor is passed' do
      let(:actor) { ArbitraryModel.create! }

      it 'will not delete a job which is not associated with the actor' do
        Reactor::Event.publish :turtle_time, at: time

        expect {
          Reactor::Event.reschedule :turtle_time, at: time + 2.hours, was: time, actor: actor
        }.to change { scheduled.size}.from(1).to(2)
      end

      it 'will delete a job associated with the actor' do
        Reactor::Event.publish :turtle_time, at: time, actor: actor

        expect {
          Reactor::Event.reschedule :turtle_time, at: time + 2.hours, was: time, actor: actor
        }.not_to change { scheduled.size}.from(1)
      end

      it 'will skip jobs of other classes' do
        OtherWorker.perform_in(1.minute, 'foo')

        expect {
          Reactor::Event.reschedule :turtle_time, at: time + 2.hours, was: time, actor: actor
        }.to change { scheduled.size}.from(1).to(2)
      end
    end
  end

  describe 'event content' do
    let(:cat) { MyModule::Cat.create }
    let(:arbitrary_model) { ArbitraryModel.create }
    let(:event_data) { {random: 'data', pet_id: cat.id, pet_type: cat.class.to_s, arbitrary_model: arbitrary_model } }
    let(:event) { Reactor::Event.new(event_data) }

    describe 'data key interaction with internals' do
      subject { event }

      describe 'getters' do
        context 'basic key value' do
          its(:random) { is_expected.to eq('data') }
        end

        context 'foreign key and foreign type' do
          its(:pet) { is_expected.to be_a MyModule::Cat }
          its('pet.id') { is_expected.to eq(MyModule::Cat.last.id) }
        end

        context 'accessing the internal __data__' do
          its(:__data__) do
            is_expected.to eq ({
                  'random' => 'data',
                  'pet_id' => cat.id,
                  'pet_type' => 'MyModule::Cat',
                  'arbitrary_model_id' => arbitrary_model.id,
                  'arbitrary_model_type' => arbitrary_model.class.name
                })
          end
        end

        context 'a key named "data"' do
          let(:event_data) { {random: 'data', data: 'info' } }
          its(:random) { is_expected.to eq('data') }
          its(:data) { is_expected.to eq 'info' }
        end
      end

      describe 'setters' do
        it 'sets simple keys' do
          event.simple = 'key'
          expect(event.__data__[:simple]).to eq('key')
        end

        it 'sets active_record polymorphic keys' do
          event.complex = cat = MyModule::Cat.create
          event.complex_id = cat.id
          event.complex_type = cat.class.to_s
        end
      end
    end

    describe '__data__' do
      let(:serialized_event) { event.__data__ }
      specify { expect(serialized_event).to be_a Hash }
      specify { expect(serialized_event[:random]).to eq('data') }
    end

    describe 'new' do
      specify { expect(event).to be_a Reactor::Event }
      specify { expect(event.pet_id).to eq(cat.id) }
      specify { expect(event.arbitrary_model_id).to eq(arbitrary_model.id) }
    end
  end
end
