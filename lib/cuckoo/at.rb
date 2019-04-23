# frozen_string_literal: true

module Cuckoo
  class At
    attr_reader :grace, :times

    def self.parse(spec:, **args)
      At.new(spec: spec, **args)
    end

    def initialize(spec:, grace: nil)
      if spec.is_a?(String)
        spec = [spec]
      end

      case spec
      when Array
        @times = spec.map { |s| SingleAt.new(s, grace: grace) }
      else
        raise ArgumentError.new("Invalid 'at' spec type: #{spec.inspect}")
      end
    end

    # "At" jobs run within the grace window following the specified times. If
    # no scheduler is free to run and misses the grace window, that run will be
    # skipped.
    def run_wanted?(last_run:, proposed:)
      expected = next_as_of(last_run)

      # never run early
      return false if proposed < expected

      # do run iff we are before the end of the grace period
      return proposed <= expected + grace
    end

    # The default grace period is the run period / 120. So example grace
    # periods for various run intervals would be:
    # - 1 day => 12 minutes
    # - 1 hour => 30 seconds
    # - 2 minutes => 1 second
    # - <2 minutes => 0
    #
    def default_grace
      (period / 120).floor
    end
  end

  class SingleAt
    DAYS_OF_WEEK = %w[
      sunday monday tuesday wednesday thursday friday saturday
    ].each_with_object({}).with_index { |(day, hash), i| hash[day] = i }

    def initialize(spec, grace: nil)
      unless spec.is_a?(String)
        raise ArgumentError.new('"at" spec must be string')
      end

      if spec =~ /\A([a-z]+)\s+(.*)\z/i
        raw_day = Regexp.last_match(1).downcase
        @day_index = parse_day_index(raw_day)

        # continue parsing rest of spec
        spec = Regexp.last_match(2)
      end

      # default to wildcards
      @hour = nil
      @minute = nil

      case spec
      when /\A(\d{1,2}):(\d\d)\z/
        @hour = Integer(Regexp.last_match(1))
        @minute = Integer(Regexp.last_match(2))
      when /\A\*{1,2}:(\d\d)\z/
        @minute = Integer(Regexp.last_match(1))
      when /\A(\d{1,2}):\*{1,2}\z/
        @hour = Integer(Regexp.last_match(1))
      when /\A\*{1,2}:\*{1,2}\z/
        nil
      else
        raise ParseError.new("Invalid 'at' spec: #{spec.inspect}")
      end

      @grace = grace || default_grace
    end

    private

    def parse_day_index(day_str)
      unless day_str.is_a?(String) && day_str.length >= 2
        raise ParseError.new("Invalid day: #{day_str.inspect}")
      end

      begin
        return DAYS_OF_WEEK.fetch(day_str)
      rescue KeyError
        DAYS_OF_WEEK.each_pair do |day, index|
          return index if day.start_with?(day_str)
        end

        raise ParseError.new("Invalid day: #{day_str.inspect}")
      end
    end

    # TODO figure out what to do about grace periods

  end
end
