# frozen_string_literal: true

require 'json'
require 'redis'

require_relative 'cuckoo/version'

module Cuckoo
  class << self
    # These are all class methods (e.g. Cuckoo.schedule)

    # Hash of configuration passed to {Redis.new}
    attr_writer :redis_config, :logger, :scheduler

    # Define scheduled jobs
    def schedule(&block)
      raise ArgumentError.new('Must pass block') unless block

      scheduler.instance_eval(&block)
    end

    # The main scheduler instance that holds all our jobs and runs them.
    # Top level Cuckoo class methods mostly point straight at this instance.
    #
    # @see Cuckoo::Scheduler
    # @return [Cuckoo::Scheduler]
    #
    def scheduler
      @scheduler ||= Scheduler.new
    end

    # Top level logger
    # @return [Logger]
    def logger
      @logger ||= Logger.new(STDERR).tap do |logger|
        logger.progname = name
      end
    end

    def redis
      @redis ||= Redis.new(redis_config)
    end

    # Hash of configuration values to pass to Redis.new
    #
    # @return [Hash]
    def redis_config
      return @redis_config if @redis_config

      begin
        @redis_config = JSON.parse(ENV.fetch('REDIS_CONFIG_JSON'))
      rescue KeyError
        raise ArgumentError.new(
          'Missing redis config. ' \
          "Call #{name}.redis_config = {...} or set REDIS_CONFIG_JSON='{...}'"
        )
      end
    end
  end
end
