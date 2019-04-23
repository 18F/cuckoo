# frozen_string_literal: true

module Cuckoo
  class Job
    attr_reader :name, :namespace, :interval, :block

    # Three procs for customizing behavior
    attr_accessor :if_proc, :middleware, :error_handler

    # @param [String] name
    # @param [String] namespace
    # @param [String, Array<String>] at Specification for {At.parse}
    # @param [Integer, String] every Specification for {Every.parse}
    # @param [Integer] grace Grace period, in seconds, applied to "at" jobs
    #   that determines how late a run is allowed to start after the specified
    #   "at" time.
    # @param [#call] if_proc This callable is used to enable/disable job
    #   running. The proc will be called with the Job instance and the current
    #   time prior to each prospective run. If the proc returns falsy, the job
    #   will not be run.
    # @param [#call] middleware This callable is used to wrap the job run
    #   block. The middleware will receive this Job instance and the run block
    #   upon each run. The middleware must then call the block, or it will not
    #   be executed.
    # @param [#call] error_handler This callable is run upon job errors. It
    #   receives the exception and this Job instance.
    #
    def initialize(name:, namespace: nil, at: nil, every: nil, grace: nil,
                   if_proc: nil, middleware: nil, error_handler: nil, &block)
      raise ArgumentError.new('Must pass job block') unless block
      raise ArgumentError.new('Must pass :at or :every') unless at || every
      raise ArgumentError.new('Cannot pass both :at and :every') if at && every

      @name = name
      @namespace = namespace

      @if_proc = if_proc
      @middleware = middleware
      @error_handler = error_handler

      validate_callables([if_proc, middleware, error_handler])

      if at
        @interval = Cuckoo::At.parse(at, grace: grace)
      elsif every
        @interval = Cuckoo::Every.parse(every)
      else
        raise ArgumentError.new('Must pass :at or :every')
      end

      @block = block
      @lock_held = false
    end

    def job_id
      [namespace, name].compact.join('::').freeze
    end

    # @see At#next_as_of
    # @see Every#next_as_of
    def next_run
      interval.next_as_of(last_run || Time.at(0))
    end

    # Fetch the last successful run time for this Job from redis.
    #
    # @return [Time, nil]
    def last_run
      res = redis.get(redis_key_last_run)
      Time.at(Integer(res)) if res
    end

    # @see Zhong.logger
    def logger
      Zhong.logger
    end

    def run_if_due(**args)
      now = Time.now.utc
      return false unless run_wanted?(now)

      unless run_if?(now)
        logger.info("Skipping run due to run_if => false: #{job_id}")
        return false
      end

      if disabled?
        logger.info("Skipping run due to disabled => true: #{job_id}")
      end

      run(**args)
    end

    def run
      logger.info("Running #{self}")

      with_lock do
        begin
          if middleware
            logger.debug('Calling middleware')
            middleware.call(self, &block)
          else
            logger.debug('Calling block')
            block.call
          end
        rescue StandardError => err
          logger.error("Error in #{self}: #{err}")
          record_last_run(error: err)
          error_handler&.call(err, self)
        else
          record_last_run
        end
      end
    end

    def to_s
      "Job <#{job_id}>"
    end

    # Acquire the Redis lock for this job and call the provided block.
    # @yield
    #
    def with_lock
      return unless acquire_lock(expiration_seconds: 15 * 60)

      yield
    ensure
      release_lock
    end

    # @return [Boolean] Whether this job has been flagged as disabled in redis.
    def disabled?
      redis.get(redis_key_disabled) || false
    end

    # Disable the job by setting a flag in redis.
    def disable
      logger.warn("Disabling #{self}")
      redis.set(redis_key_disabled, generate_identifier)
    end

    # Disable the job by clearing a flag in redis.
    def enable
      logger.warn("Enabling #{self}")
      redis.del(redis_key_disabled)
    end

    private

    # @see Interval#run_wanted?
    def run_wanted?(time)
      interval.run_wanted?(last_run: last_run, proposed: time)
    end

    def run_if?(time)
      @if_proc.nil? || @if_proc.call(self, time)
    end

    # @see Zhong.redis
    def redis
      Zhong.redis
    end

    def redis_key_lock
      "cuckoo-lock:#{job_id}"
    end

    def redis_key_last_run
      "cuckoo-last-run:#{job_id}"
    end

    def redis_key_disabled
      "cuckoo-disabled:#{job_id}"
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

    def acquire_lock(expiration_seconds:)
      logger.info("Attempting to acquire lock on #{job_id.inspect} " \
                  "for #{expiration_seconds.inspect} seconds")

      if @lock_held
        raise ArgumentError.new('Double lock acquisition')
      end

      id = generate_identifier
      result = redis.set(redis_key_lock, id, ex: expiration_seconds, nx: true)

      if result
        @lock_held = true
        logger.debug("Acquired lock, id: #{id}")
        id
      else
        logger.debug('Failed to acquire lock')
        logger.debug { "Lock currently held by: #{redis.get(redis_key_lock)}" }
        false
      end
    end

    # Release the lock in redis by deleting the lock key. Raises an error if
    # this instance doesn't hold the lock (programmer error). Warns and returns
    # nil if we thought we held the lock, but actually Redis shows that someone
    # else holds it (concurrency error).
    def release_lock(id)
      raise 'No lock is held' unless @lock_held

      holder_id = redis.get(redis_key_lock)
      if holder_id.nil?
        logger.warn('Cannot release lock, not held by anyone')
        return
      end

      logger.info("Releasing lock on #{self}")
      @lock_held = false

      if holder_id != id
        logger.warn('Cannot release lock, currently ' \
                    "held by someone else: #{holder_id.inspect}")
        return
      end

      redis.del(redis_key_lock)

      logger.debug('Lock released')
    end

    # Record information about the last job run. If error is not given, job is
    # assumed to have been successful.
    #
    # @param [Exception, nil] error The error to report, if a job was not
    #   successful.
    #
    def record_last_run(error: nil)
      raise 'Must have lock' unless @lock_held

      info = {
        host: Socket.gethostname,
        pid: Process.pid,
        time: Time.now.utc,
      }

      if error
        info[:error] = error.to_s
        info[:success] = false
      else
        info[:success] = true
      end

      redis.set(redis_key_last_run, info.to_json)
    end

    # Check that provided objects are callable.
    #
    # @param [Array<#call>] callables An array of callables to validate.
    #
    # @raise ArgumentError if provided objects don't respond to `.call`
    def validate_callables(callables)
      callables.each do |c|
        next unless c
        next if c.respond_to?(:call)

        raise ArgumentError.new("Callback must respond to .call: #{c.inspect}")
      end
    end
  end
end
