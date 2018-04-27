# frozen_string_literal: true

module Reactor
  class UnconfiguredWorkerError < StandardError; end
  class EventHandlerAlreadyDefined < StandardError; end
  class UndeliverableMailError < StandardError; end
end
