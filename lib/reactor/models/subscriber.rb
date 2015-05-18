class Reactor::Subscriber < ActiveRecord::Base
  include GlobalID::Identification
  attr_accessor :event

  def event_name=(event)
    write_attribute :event_name, event.to_s
  end

  def fire(data)
    self.event = Reactor::Event.new(data)
    instance_exec &self.class.on_fire
    self
  end

  class << self
    def on_fire(&block)
      if block
        @fire_block = block
      end
      @fire_block
    end

    def fire(subscriber_id, data)
      Reactor::Subscriber.find(subscriber_id).fire data
    end
  end
end
