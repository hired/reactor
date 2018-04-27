# frozen_string_literal: true

# EventWorker is an abstract worker for handling events defined by on_event.
# You can create handlers by subclassing and redefining the configuration class
# methods, or by using Reactor::Workers::EventWorker.dup and overriding the
# methods on the new class.
module Reactor
  module Workers
    class EventWorker
      include Reactor::Workers::Configuration
    end
  end
end
