class Reactor::Jobs::SubscriberJob < Reactor::Jobs::Base
  def perform(subscriber, data)
    subscriber.fire data
  end
end
