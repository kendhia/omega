# Defines the LocationRunner and Runner classes, core to the motel engine,
# and is responsible for managing locations and moving them according to
# their corresponding movement_strategies
#
# Copyright (C) 2012 Mohammed Morsi <mo@morsi.org>
# Licensed under the AGPLv3+ http://www.gnu.org/licenses/agpl.txt

require 'thread'
require 'singleton'
require 'rjr/common'

module Motel

# Motel::Runner is a singleton class/object which acts as the primary
# mechanism to run locations in the system. It contains a thread pool
# which contains a specified number of threads which to move the managed
# locations in accordance to their location strategies.
class Runner
  include Singleton

  # For testing purposes
  attr_reader :terminate, :run_thread

   # Runner initializer
   #
   # @param [Hash] args hash of options to initialize runner with, currently unused
  def initialize(args = {})
    # is set to true upon runner termination
    @terminate = false

    # TODO use ruby tree to store locations w/ heirarchy ?
    # management queues, locations to be scheduled and locations to be run
    @schedule_queue = []
    @run_queue = []


    # locks protecting queues from concurrent access and conditions indicating queues have items
    @schedule_lock  = Mutex.new
    @run_lock       = Mutex.new
    @schedule_cv    = ConditionVariable.new
    @run_cv         = ConditionVariable.new

    @run_thread = nil
  end

  # Run the specified block of code as a protected operation.
  #
  # This should be used when updating any motel entities outside
  # the scope of runner operations to protect them from concurrent access.
  #
  # @param [Array<Object>] args catch-all array of arguments to pass to block on invocation
  # @param [Callable] bl block to invoke
  def safely_run(*args, &bl)
    @schedule_lock.synchronize {
      @run_lock.synchronize {
        bl.call *args
      }
    }
  end


  # Return complete list of locations being managed/tracked
  #
  # @return [Array<Motel::Location>]
  def locations
    ret = []
    # would rather not have to lock these both at the same time,
    # but if locked independenly, the queues can be maniupulated
    # inbetween the locks
    @schedule_lock.synchronize {
      @run_lock.synchronize {
        @schedule_queue.each { |l| ret << l }
        @run_queue.each { |l| ret << l }
      }
    }
    return ret
  end

  # Return boolean indicating if the specified location id is tracked by this runner
  #
  # @param [Integer] id id of location to look for
  # @return [true,false] indicating if location is tracked locally
  def has_location?(id)
    !locations.find { |l| l.id == id }.nil?
  end

  # Empty the list of locations being managed/tracked
  def clear
    @schedule_lock.synchronize {
      @run_lock.synchronize {
        @schedule_queue.clear
        @run_queue.clear
    }}
  end

  # Add location to runner to be managed.
  #
  # After this is called, the location's movement strategy's move method will be invoked periodically
  # @param [Motel::Location] location location to add the the run queue
  # @return [Motel::Location] location just added
  def run(location)
    @schedule_lock.synchronize {
      # autogenerate location.id if nil
      if location.id.nil?
        @run_lock.synchronize {
          i = 1
          until false
            break if @schedule_queue.find { |l| l.id == i }.nil? && @run_queue.find { |l| l.id == i }.nil?
            i += 1
          end
          location.id = i
        }
      end

      RJR::Logger.debug "adding location #{location.id} to runner queue"
      @schedule_queue.push location
      @schedule_cv.signal
    }
    return location
  end

  # Wrapper around run, except return 'self' when done
  def <<(location)
    run(location)
    return self
  end

  # Start running the locations.
  #
  # If :async => true is passed in, this will immediately return,
  # else this will block until stop is called.
  #
  # @param [Hash] args option array of args which can be used to configure runner
  # @option args [true,false] :async boolean indicating if we should immediately return or not
  # @option args [Integer] :num_threads the number of worker threads to launch, currently unusued
  def start(args = {})
    @num_threads = 5
    @num_threads = args[:num_threads] if args.has_key? :num_threads
    @terminate = false

    if args.has_key?(:async) && args[:async]
      RJR::Logger.debug "starting async motel runner"
      @run_thread = Thread.new { run_cycle }
    else
      RJR::Logger.debug "starting motel runner"
      run_cycle
    end

  end

  # Stop locations movement
  def stop
    RJR::Logger.debug "stopping motel runner"
    @terminate = true
    @schedule_lock.synchronize {
      @schedule_cv.signal
    }
    @run_lock.synchronize {
      @run_cv.signal
    }
    join
    RJR::Logger.debug "motel runner stopped"
  end

  # Block until runner is shutdown before returning
  def join
    @run_thread.join unless @run_thread.nil?
    @run_thread = nil
  end

  # Save state of the runner to specified io stream
  def save_state(io)
    locs = locations
    @schedule_lock.synchronize {
      @run_lock.synchronize {
        locs.each { |loc| io.write loc.to_json + "\n" }
      }
    }
  end

  # Restore state of the runner from the specified io stream
  def restore_state(io)
    io.each { |json|
      entity = JSON.parse(json)
      if entity.is_a?(Motel::Location)
        run entity
      end
    }
  end

  private

    # Internal helper method performing main runner operations
    def run_cycle
      # location ids which are currently being run -> their run timestamp
      location_timestamps = {}

      # scheduler thread, to add locations to the run queue
      scheduler = Thread.new {
        until @terminate
          tqueue       = []
          locs_to_run  = []
          empty_queue  = true
          min_delay    = nil

          @schedule_lock.synchronize {
            # if no locations are to be scheduled, block until there are
            @schedule_cv.wait(@schedule_lock) if @schedule_queue.empty?
            @schedule_queue.each { |l| tqueue << l }
          }

          # run through each location to be scheduled to run, see which ones are due
          tqueue.each { |loc|
            location_timestamps[loc.id] = Time.now unless location_timestamps.has_key?(loc.id)
            locs_to_run << loc if loc.movement_strategy.step_delay < Time.now - location_timestamps[loc.id]
          }

          # add those the the run queue, signal runner to start operations if blocking
          @schedule_lock.synchronize {
            @run_lock.synchronize{
              locs_to_run.each { |loc| @run_queue << loc ; @schedule_queue.delete(loc) }
              empty_queue = (@schedule_queue.size == 0)
              @run_cv.signal unless locs_to_run.empty?
            }
          }

          # if there are locations still to be scheduled, sleep for the smallest step_delay
          unless empty_queue
            # we use locations instead of @schedule_queue here since a when the scheduler is
            # sleeping a loc w/ a smaller step_delay may complete running and be added back to the scheduler
            min_delay= locations.sort { |a,b| 
              a.movement_strategy.step_delay <=> b.movement_strategy.step_delay 
            }.first.movement_strategy.step_delay
            sleep min_delay
          end
        end
      }

      # until we are told to stop
      until @terminate
        locs_to_schedule = []
        tqueue           = []

        @run_lock.synchronize{
          # wait until we have locations to run
          @run_cv.wait(@run_lock) if @run_queue.empty?
          @run_queue.each { |l| tqueue << l }
        }

        # run through each location to be run, perform actual movement, invoke callbacks
        tqueue.each { |loc|
          RJR::Logger.debug "runner moving location #{loc.id} at #{loc.coordinates.join(",")} via #{loc.movement_strategy.to_s}"
          #RJR::Logger.debug "#{loc.movement_callbacks.length} movement callbacks, #{loc.proximity_callbacks.length} proximity callbacks"

          # store the old location coordinates for comparison after the movement
          old_coords = [loc.x, loc.y, loc.z]

          elapsed = Time.now - location_timestamps[loc.id]
          safely_run { # TODO not a huge fan of using global sync lock here, would rather use a location specific one (so long as other updates to the location make use of it as well)
            loc.movement_strategy.move loc, elapsed
          }
          location_timestamps[loc.id] = Time.now

          # invoke movement_callbacks for location moved
          # TODO invoke these async so as not to hold up the runner
          # TODO delete movement callbacks after they are invoked?
          # TODO prioritize callbacks registered over the local rjr transport
          #      over others
          # make sure to keep these in sync w/ those invoked in the rjr adapter "update_location" handler
          loc.movement_callbacks.each { |callback|
            callback.invoke(loc, *old_coords)
          }

          locs_to_schedule << loc
        }

        # invoke all proximity_callbacks
        # see comments about movement_callbacks above
        locations.each { |loc|
          loc.proximity_callbacks.each { |callback|
            callback.invoke(loc)
          }
        }


        # add locations back to schedule queue
        @schedule_lock.synchronize{
          @run_lock.synchronize{
            locs_to_schedule.each { |loc| @schedule_queue << loc ; @run_queue.delete(loc) }
            @schedule_cv.signal unless locs_to_schedule.empty?
          }
        }
      end

      scheduler.join
    end

end

end # module motel
