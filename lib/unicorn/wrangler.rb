require "unicorn/wrangler/version"

module Unicorn
  class Wrangler
    attr_reader :command, :pidfile, :grace_period
    attr_accessor :unicorn

    def initialize(command, options = {})
      @command = command
      @pidfile = File.expand_path(options[:pidfile] || 'unicorn.pid')
      @grace_period = options[:grace_period] || 60
      @verbose = options[:verbose]
      @unicorn = UnicornProcess.from_pidfile(@pidfile)
    end

    class UnicornProcess
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
        puts "Sending signal #{msg} to #{pid}"
        Process.kill msg, pid
      end

      def reload(grace_period)
        signal "USR2"
        sleep grace_period
        reloaded_unicorn = UnicornProcess.from_pidfile(pidfile)
        if reloaded_unicorn && pid != reloaded_unicorn.pid
          terminate
          reloaded_unicorn
        else
          raise "unicorn didn't reload correctly within grace period (was pid #{pid})"
        end
      end

      def launch_assassin(grace_period)
        if running? && !@assassin_launched
          @assassin_launched = true
          puts "preparing to kill unicorn #{pid} in #{grace_period} seconds"
          unless fork
            File.write(assassin_pidfile, Process.pid.to_s)

            trap 'TERM' do
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
          Process.kill 'TERM', assassin_pid
        end
      rescue Errno::ESRCH
      end

      def assassin_pidfile
        pidfile + ".assassin"
      end

      def terminate
        if running?
          signal 'TERM'
        else
          "Attempt to terminate #{pid} failed as process not running"
        end
      end

      def verbose(message)
        self.class.verbose(message)
      end

      def self.verbose(message)
        Unicorn::Wrangler.verbose(message)
      end

      def self.wait_for(&block)
        until block.call
          sleep 0.1
        end
      end

      def self.start(pidfile, command)
        Process.spawn(command, pgroup: true)
        wait_for { File.exist?(pidfile) }
        new(pidfile)
      end

      def self.from_pidfile(pidfile)
        File.exist?(pidfile) && new(pidfile)
      end
    end

    def start
      setup_signal_handlers

      if unicorn && unicorn.running?
        self.unicorn = reload_unicorn
      else
        self.unicorn = UnicornProcess.start(pidfile, command)
        sleep grace_period
      end

      if unicorn.running?
        verbose "Unicorn running on #{unicorn.pid}"
        loop_while_unicorn_runs
      else
        verbose "Unable to start unicorn.  Exiting."
      end
    end

    def setup_signal_handlers
      trap_signals(:HUP) { reload_unicorn }
      trap_signals(:QUIT, :INT, :TERM) do |signal|
        kill_unicorn_after_delay
        exit
      end
    end

    def reload_unicorn
      self.unicorn = unicorn.reload(grace_period) if unicorn
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

    def trap_signals(*signals, &block)
      signals.map(&:to_s).each do |signal|
        trap(signal) do
          verbose "received #{signal} (managing #{unicorn.pid})"
          block.call signal
        end
      end
    end

    def wait_for(&block)
      until block.call
        sleep 0.1
      end
    end

    def kill_unicorn_after_delay
      unicorn.launch_assassin(grace_period) if unicorn
    end

    def verbose(message)
      self.class.verbose(message)
    end

    def self.verbose(message)
      puts message if @verbose
    end
  end
end
