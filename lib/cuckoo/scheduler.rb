# frozen_string_literal: true

require 'json'
require 'socket'

require 'redis'

module Cuckoo
  class Scheduler

    attr_reader :jobs

    def initialize
      @jobs = {}
      @callbacks = {}

      @cur_namespace = nil
    end

    # Define jobs within a namespace.
    #
    # @param [String] name The name of the namespace
    # @yield [Scheduler] Must pass a block, which receives this scheduler
    #   instance as an argument.
    #
    def namespace(name)
      if @cur_namespace
        raise ArgumentError.new(
          "Cannot nest namespaces. #{name} would be inside #{@cur_namespace}"
        )
      end

      begin
        @cur_namespace = name.to_s
        yield(self)
      ensure
        @cur_namespace = nil
      end
    end

    # Create a job that runs every `period`. This may be an integer number of
    # seconds or a string period specification, like "5 minutes".
    #
    # @see Job#initialize
    #
    # @param [String] period
    # @param [String] name The unique job name
    # @yield Invokes the block containing the actual job code
    #
    def every(period, name, **job_config, &blk)
      raise ArgumentError.new('Must specify period') unless period

      job = Job.new(namespace: @cur_namespace, name: name, every: period,
                    **job_config, &blk)
      add_job(job)
    end

    # Create a job that runs at a specific `time_spec`. This must be a string
    # time specification, like "**:30", or an array of such strings.
    #
    # @see Job#initialize
    #
    # @param [String, Array<String>] time_spec The time specification
    # @param [String] name The unique job name
    # @yield Invokes the block containing the actual job code
    #
    def at(time_spec, name, **job_config, &blk)
      raise ArgumentError.new('Must specify time_spec') unless time_spec

      job = Job.new(namespace: @cur_namespace, name: name, at: time_spec,
                    **job_config, &blk)
      add_job(job)
    end

    # @param [Cuckoo::Job] job
    def add_job(job)
      if jobs.include?(job.job_id)
        raise DuplicateJobError.new("Duplicate job id: #{job.job_id.inspect}")
      end

      jobs[job.job_id] = job
    end

    # Generate a lock identifier that communicates enough useful information for
    # debugging. We'll log this identifier when acquiring the lock.
    #
    # This identifier includes the hostname, PID, a random UUID, and the time.
    #
    # @return [String]
    #
    def generate_identifier
      {
        host: Socket.gethostname,
        pid: Process.pid,
        rand: SecureRandom.uuid,
        time: Time.now.utc,
      }.to_json
    end

    # Call block if it hasn't run in the last +seconds+.
    #
    # @param [Integer] seconds The minimum number of seconds between runs.
    # @param [String] name A label for the block that will be used as the
    #   key name for the lock recording the last run time.
    #
    # @example Run a job if it hasn't run in the last 5 minutes
    #   run_if_cron_due(name: 'my-5min-job', seconds: 300) do
    #     do_the_thing
    #   end
    #
    def run_if_cron_due(name:, seconds:)
      raise ArgumentError.new('must pass block') unless block_given?

      if acquire_lock(full_label: label_for(name), expiration_seconds: seconds)
        logger.info("Running job for #{name.inspect}")
        yield
      else
        logger.info("Job for #{name.inspect} is not due to be run yet")
        false
      end
    end

    # Get the time remaining until the next run of the given job. This is
    # equivalent to the TTL remaining on the Redis key. The result may be
    # negative if the key does not exist or has no TTL.
    #
    # @param [String] lock_label A label for the job
    # @return [Integer]
    #
    def time_until_next_run(lock_label:)
      label = label_for(lock_label)
      logger.debug("Checking time until next run of #{label.inspect}")
      redis.ttl(label)
    end

    # Get the current holder of the lock for the given job.
    #
    # @param [String] lock_label A label for the job
    # @return [String, nil]
    #
    def get_current_lock_id(lock_label:)
      label = label_for(lock_label)
      logger.debug("Getting any current lock held for #{label.inspect}")
      redis.get(label)
    end

    private

    # Add the custom prefix to the lock label so it doesn't conflict with any
    # other Redis keys.
    def label_for(label)
      'cron-lock:' + label
    end

    def acquire_lock(full_label:, expiration_seconds:)
      logger.info("Attempting to acquire lock on #{full_label.inspect} " \
                  "for #{expiration_seconds.inspect} seconds")
      id = generate_identifier
      result = redis.set(full_label, id, ex: expiration_seconds, nx: true)

      if result
        logger.info("Acquired lock, id: #{id}")
      else
        logger.info('Failed to acquire lock')
        logger.info("Lock currently held by: #{redis.get(full_label)}")
      end

      result
    end

    def default_logger
      l = Logger.new(STDERR)
      l.progname = self.class.name
      l
    end
  end
end
