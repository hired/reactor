module Reactor::Arguments
  include ActiveJob::Arguments
  extend self

  TIME_KEY = 'ReactorTimeObject'

  private

  def serialize_argument_with_reactor_time_support(argument)
    case argument
      when Time
        {Reactor::Arguments::TIME_KEY => true, 'value' => argument.to_i}
      else
        serialize_argument_without_reactor_time_support(argument)
    end
  end
  alias_method_chain :serialize_argument, :reactor_time_support

  def deserialize_argument_with_reactor_time_support(argument)
    if argument.class <= Hash && argument.has_key?(TIME_KEY)
      Time.at argument['value']
    else
      deserialize_argument_without_reactor_time_support(argument)
    end
  end
  alias_method_chain :deserialize_argument, :reactor_time_support
end
