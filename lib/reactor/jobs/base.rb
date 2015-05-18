class Reactor::Jobs::Base < ActiveJob::Base
  def serialize_arguments(serialized_args)
    Reactor::Arguments.serialize(serialized_args)
  end

  def deserialize_arguments(serialized_args)
    Reactor::Arguments.deserialize(serialized_args)
  end
end
