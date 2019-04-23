# frozen_string_literal: true

module Cuckoo
  class Every < Interval
    attr_reader :period

    def self.parse(spec, **args)
      Every.new(spec: spec, **args)
    end

    def initialize(spec:)
      case spec
      when Integer
        @period = spec
      when Numeric
        @period = Integer(spec)
      when /\A(\d+) (sec|secs|second|seconds)\z/
        @period = Integer(Regexp.last_match(1))
      when /\A(\d+) (min|mins|minute|minutes)\z/
        @period = Integer(Regexp.last_match(1)) * 60
      when /\A(\d+) (hour|hours)\z/
        @period = Integer(Regexp.last_match(1)) * 3600
      when /\A(\d+) (day|days)\z/
        @period = Integer(Regexp.last_match(1)) * 3600 * 24
      else
        raise ParseError.new("Could not parse 'every' spec: #{spec.inspect}")
      end

      if @period < 1
        raise ParseError.new('Period must be >= 1 second')
      end
    end

    def next_as_of(time)
      time + period
    end

    # "Every" jobs run at the earliest opportunity following each interval,
    # even if they are late.
    def run_wanted?(last_run:, proposed:)
      expected = next_as_of(last_run)

      # never run early
      return false if proposed < expected

      # run if on time or late
      return true
    end
  end
end
