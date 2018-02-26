module Reactor
  TEST_MODE_SUBSCRIBERS = Set.new
  @@test_mode = false

  module_function

  def test_mode?
    @@test_mode
  end

  def test_mode!
    @@test_mode = true
  end

  def disable_test_mode!
    @@test_mode = false
  end

  def in_test_mode
    test_mode!
    (yield if block_given?).tap { disable_test_mode! }
  end

  def test_mode_subscribers
    TEST_MODE_SUBSCRIBERS
  end

  def enable_test_mode_subscriber(klass)
    test_mode_subscribers << klass
  end

  def disable_test_mode_subscriber(klass)
    test_mode_subscribers.delete klass
  end

  def with_subscriber_enabled(klass)
    enable_test_mode_subscriber klass
    yield if block_given?
  ensure
    disable_test_mode_subscriber klass
  end

  def with_subscriber_disabled(klass)
    disable_test_mode_subscriber klass
    yield if block_given?
  ensure
    enable_test_mode_subscriber klass
  end

  def clear_test_subscribers!
    test_mode_subscribers.each {|klass| test_mode_subscribers.delete klass }
  end

  def test_mode_subscriber_enabled?(subscriber)
    test_mode_subscribers.include?(subscriber)
  end
end
