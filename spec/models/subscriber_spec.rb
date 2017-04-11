require 'spec_helper'

class MySubscriber < Reactor::Subscriber
  attr_accessor :was_called

  on_fire do
    self.was_called = true
  end
end

describe Reactor::Subscriber do

  describe 'fire' do
    subject { MySubscriber.create(event_name: :you_name_it).fire some: 'random', event: 'data' }

    its(:event) { is_expected.to be_a Reactor::Event }
    its('event.some') { is_expected.to eq('random') }

    it 'executes block given' do
      expect(subject.was_called).to be_truthy
    end
  end

  describe 'fire_async' do
    let(:klass) { MySubscriber }
    let(:subscriber) { klass.create!(event_name: :you_name_it) }
    subject { subscriber }

    it 'executes block give' do
      expect_any_instance_of(klass).to receive(:fire).with(
        some: 'random', event: 'data'
      )
      klass.fire_async subscriber.id, some: 'random', event: 'data'
    end
  end


  describe 'matcher' do
    before { MySubscriber.create!(event_name: '*') }
    after { MySubscriber.destroy_all }

    it 'can be set to star to bind to all events' do
      expect_any_instance_of(MySubscriber).to receive(:fire).with(hash_including('random' => 'data', 'event' => 'this_event'))
      Reactor::Event.publish(:this_event, {random: 'data'})
    end
  end

  describe 'SubscriberWorker' do
    let(:klass) { Reactor::Subscriber::SubscriberWorker }
    let(:subscriber) { MySubscriber.create!(event_name: :you_name_it) }
    let(:event_data) { Hash[some: 'random', event: 'data'] }

    it 'fires passed in subscriber' do
      expect_any_instance_of(MySubscriber).to receive(:fire).with(event_data)
      klass.new.perform(subscriber.id, event_data)
    end
  end
end
