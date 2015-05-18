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


  describe 'matcher' do
    it 'can be set to star to bind to all events' do
      s = MySubscriber.create!(event_name: '*')
      expect(Reactor::Jobs::SubscriberJob).to receive(:perform_later).with(s, hash_including('random' => 'data', 'name' => 'this_event'))
      Reactor::Event.publish(:this_event, random: 'data')
    end
  end
end
