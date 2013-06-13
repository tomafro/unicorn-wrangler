require "unicorn/wrangler/version"

module Unicorn
  class Wrangler
    attr_reader :command, :pidfile, :startup_period, :tick_period, :verbose

    def initialize(command, options = {})
      @command = command
      @pidfile = File.expand_path(options[:pidfile] || 'unicorn.pid')
      @startup_period = options[:startup] || 60
    end

    def start
      trap_signals(:QUIT, :INT, :TERM) { exit }

      if unicorn_running?
        restart_unicorn
      else
        Process.spawn(command, pgroup: true)
        wait_for { unicorn_running? }
      end

      loop do
        exit unless unicorn_running?
        sleep 1
      end
    end

    private

    def trap_signals(*signals, &block)
      signals.map(&:to_s).each do |signal|
        trap(signal) do
          block.call signal
        end
      end
    end

    def restart_unicorn
      original_pid = unicorn_pid
      Process.kill "USR2", unicorn_pid
      wait_for { unicorn_pid != original_pid }
      sleep startup_period
      Process.kill "TERM", original_pid
    end

    def unicorn_pid
      File.exist?(pidfile) && File.read(pidfile).to_i
    end

    def unicorn_running?
      unicorn_pid && Process.getpgid(unicorn_pid)
    rescue Errno::ESRCH
      false
    end

    def wait_for(&block)
      until block.call
        sleep 0.1
      end
    end
  end
end
