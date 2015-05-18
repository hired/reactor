module Reactor::Publishable
  extend ActiveSupport::Concern
  include GlobalID::Identification

  def publish(name, data = {})
    Reactor::Event.publish(name, {actor: self}.merge(data))
  end
end
