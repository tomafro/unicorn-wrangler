require 'unicorn/wrangler/version'
require 'logger'

module Unicorn
  class Wrangler
    class << self
      def logger
        @logger ||= Logger.new(STDOUT)
      end
    end

    module Utils
      def warn(message)
        Wrangler.logger.warn(message)
      end

      def debug(message)
        Thread.new do
          Wrangler.logger.debug(message)
        end.join
      end

      def trap_signals(*signals, &block)
        signals.map(&:to_s).each do |signal|
          trap(signal) do
            debug "received #{signal} (watching #{unicorn.pid})"
            block.call signal
          end
        end
      end

      def wait_for(seconds, &block)
        end_time = Time.now + seconds
        until Time.now > end_time || block.call
          sleep 0.1
        end
        block.call
      end
    end

    class UnicornProcess
      extend Utils
      include Utils

      attr_reader :pid, :pidfile

      def initialize(pidfile)
        @pidfile = pidfile
        @pid = File.read(pidfile).to_i
        recall_assassin
      end

      def running?
        Process.getpgid(pid)
      rescue Errno::ESRCH
        false
      end

      def signal(msg)
        debug "Sending signal #{msg} to #{pid}"
        Process.kill msg.to_s, pid
      end

      def reload(grace_period)
        signal :USR2
        if wait_for(grace_period) { reloaded_unicorn }
          Thread.new do
            sleep grace_period
            terminate
          end
          reloaded_unicorn
        else
          raise "unicorn didn't reload correctly within grace period (was pid #{pid})"
        end
      end

      def reloaded_unicorn
        reloaded = UnicornProcess.from_pidfile(pidfile)
        if reloaded && pid != reloaded.pid
          reloaded
        end
      end

      def launch_assassin(grace_period)
        if running? && !@assassin_launched
          @assassin_launched = true
          debug "preparing to kill unicorn #{pid} in #{grace_period} seconds"
          unless fork
            $0 = "unicorn-wrangler (waiting to kill #{pid})"
            File.write(assassin_pidfile, Process.pid.to_s)

            trap_signals :TERM do
              debug "Trapped and killed assassin"
              exit
            end

            Process.setsid
            sleep grace_period
            terminate
            File.delete(assassin_pidfile)
          end
        end
      end

      def recall_assassin
        if File.exist?(assassin_pidfile)
          assassin_pid = File.read(assassin_pidfile).to_i
          debug "Recalling assassin with pid #{assassin_pid}"
          Process.kill 'KILL', assassin_pid
          File.delete assassin_pidfile
        end
      rescue Errno::ESRCH
      end

      def assassin_pidfile
        pidfile + ".assassin"
      end

      def terminate
        if running?
          signal :TERM
        else
          warn "Attempt to terminate #{pid} failed as process not running"
        end
      end

      def self.start(pidfile, command)
        Process.spawn(command, pgroup: true)
        wait_for(60) { File.exist?(pidfile) }
        new(pidfile)
      end

      def self.from_pidfile(pidfile)
        File.exist?(pidfile) && new(pidfile)
      end
    end

    class Main
      include Utils
      extend Utils

      attr_reader :command, :pidfile, :grace_period
      attr_accessor :unicorn

      def initialize(command, options = {})
        @command = command
        @pidfile = File.expand_path(options[:pidfile] || 'unicorn.pid')
        @grace_period = options[:grace_period] || 60
        Wrangler.logger.level = Logger::DEBUG if options[:verbose]
        @unicorn = UnicornProcess.from_pidfile(@pidfile)
      end

      def start
        $0 = 'unicorn-wrangler (starting up)'
        setup_signal_handlers

        if unicorn && unicorn.running?
          self.unicorn = unicorn.reload(grace_period)
        else
          self.unicorn = UnicornProcess.start(pidfile, command)
          wait_for(grace_period) { unicorn.running? }
        end

        if unicorn.running?
          debug "Unicorn running on #{unicorn.pid}"
          $0 = "unicorn-wrangler (monitoring #{unicorn.pid})"
          loop_while_unicorn_runs
        else
          debug "Unable to start unicorn.  Exiting."
        end
      end

      def setup_signal_handlers
        trap_signals(:HUP)  do
          self.unicorn = unicorn.reload(grace_period) if unicorn
        end

        trap_signals(:QUIT, :INT, :TERM) do |signal|
          unicorn.launch_assassin(grace_period) if unicorn
          exit
        end
      end

      def loop_while_unicorn_runs
        loop do
          if unicorn.running?
            sleep 0.1
          else
            exit
          end
        end
      end
    end
  end
end
