# frozen_string_literal: true

module Cuckoo

  # Base class for At and Every interval classes.
  #
  # @abstract
  #
  class Interval
    # Must be overridden in subclasses
    def self.parse
      raise NotImplementedError.new
    end

    def next_as_of(time)
      raise NotImplementedError.new("Subclass must define using #{time}")
    end

    def run_wanted?(last_run:, proposed:)
      raise NotImplementedError.new(
        "Subclass must define using #{last_run} and #{proposed}"
      )

    end

    # Must be overridden in subclasses
    def next_run
      raise NotImplementedError.new
    end
  end
end
