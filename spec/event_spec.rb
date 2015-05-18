require 'spec_helper'

module MyModule
  class Pet < ActiveRecord::Base
    include GlobalID::Identification
  end

  class Cat < Pet
  end
end

class ArbitraryModel < ActiveRecord::Base
  include GlobalID::Identification
end

class OtherWorker < Reactor::Jobs::Base
end

describe Reactor::Event do

  let(:model) { ArbitraryModel.create! }
  let(:event_name) { :user_did_this }

  describe 'publish' do
    it 'fires the first perform and sets message event_id' do
      expect(Reactor::Event).to receive(:perform_later).with(name: event_name.to_s, actor_id: '1')
      Reactor::Event.publish(:user_did_this, actor_id: '1')
    end
  end

  describe 'perform' do
    let!(:db_subscriber) { Reactor::Subscriber.create(event_name: :user_did_this) }
    it 'fires all db subscribers' do
      Timecop.freeze do
        expect(Reactor::Jobs::SubscriberJob).to receive(:perform_later)
                                                    .with(db_subscriber,
                                                          hash_including(
                                                              name: event_name.to_s,
                                                              actor: model,
                                                              fired_at: Time.current))
        Reactor::Event.perform_now(name: event_name.to_s, actor: model)
      end
    end
  end

  describe 'event content' do
    let!(:cat) { MyModule::Cat.create }
    let(:arbitrary_model) { ArbitraryModel.create }
    let(:time) { Time.current }
    let(:event_data) { {random: 'data', arbitrary_model: arbitrary_model, pet: cat, fired_at: time } }
    let(:event) { Reactor::Event.new(event_data) }

    describe 'data key fallthrough' do
      subject { event }

      it 'sets and gets simple keys' do
        event.simple = 'key'
        expect(event.simple).to eq('key')
      end

      it 'delegates serialization to active job extension' do
        event.complex = cat = MyModule::Cat.create
        expect(event.complex).to eql(cat)

        event.time = time = Time.current
        expect(event.time).to eql(time)

        expect { event.serialize }.to_not raise_exception
      end
    end

    describe 'new' do

      specify { expect(event).to be_a Reactor::Event }
      specify { expect(event.arbitrary_model).to eq(arbitrary_model) }
      specify { expect(event.random).to eq('data') }
      specify { expect(event.fired_at).to eq(time) }
    end
  end
end
