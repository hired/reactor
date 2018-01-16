require 'spec_helper'

describe Reactor::Subscription do

  describe '#initialize builds a worker class' do
    subject! do
      described_class.new(source: Pet, event_name: :pooped) do
      end
    end

    specify do
      expect(Reactor::StaticSubscribers::Pet::PoopedHandler < Reactor::Workers::EventWorker)
          .to be true
    end

    describe 'when subscriber object has namespace of arbitrary length' do
      subject! do
        described_class.new(source: Reactor::Subscription, event_name: :pooped) do
        end
      end

      specify do
        expect(Reactor::StaticSubscribers::Reactor::Subscription::PoopedHandler <
                   Reactor::Workers::EventWorker)
            .to be true
      end
    end
  end

  describe '.build_handler_name' do
    let(:event_name) { :kitten_sleeping }

    subject { described_class.build_handler_name(event_name) }

    it 'should camelize event name' do
      expect(subject).to eq('KittenSleepingHandler')
    end

    context 'with wildcard event name' do
      let(:event_name) { '*' }
      it { is_expected.to eq('WildcardHandler') }
    end

    context 'with handler name specified' do
      let(:result) { 'SleepyKittenHandler' }
      subject { described_class.build_handler_name(event_name, handler_name) }

      context 'as snake_cased' do
        let(:handler_name) { :sleepy_kitten_handler }
        it { is_expected.to eq(result) }
      end

      context 'as CamelCased' do
        let(:handler_name) { 'SleepyKittenHandler' }
        it { is_expected.to eq(result) }
      end
    end
  end

  describe 'building a new subscriptiong' do
    class SleepyKittenSubscriber ; end

    let(:source) { SleepyKittenSubscriber }
    let(:event_name) { :kitten_sleeping }
    let(:action) { double('Callable Action') }

    context 'for delayed async worker' do
      let(:delay) { 10.minutes }
    end

    context 'for synchronous runners' do
      let(:async) { false }
    end

    context 'with handler name specified' do
      let(:handler_name) { :sleepy_kitten_streaming_handler }
    end
  end

end
