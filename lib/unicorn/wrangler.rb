require "unicorn/wrangler/version"

module Unicorn
  class Wrangler
    attr_reader :command, :pidfile, :grace_period

    def initialize(command, options = {})
      @command = command
      @pidfile = File.expand_path(options[:pidfile] || 'unicorn.pid')
      @grace_period = options[:grace_period] || 60
    end

    def start
      trap_signals(:HUP) { restart_unicorn }
      trap_signals(:QUIT, :INT, :TERM) do |signal|
        kill_unicorn_after_delay
        exit
      end

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
          puts "unicorn-wrangler #{Process.pid} received #{signal} (managing #{unicorn_pid})"
          block.call signal
        end
      end
    end

    def restart_unicorn
      original_pid = unicorn_pid
      Process.kill "USR2", unicorn_pid
      wait_for { unicorn_pid != original_pid }
      sleep grace_period
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

    def kill_unicorn_after_delay
      if unicorn_running?
        puts "Preparing to kill unicorn in #{grace_period} seconds"
        unless fork
          Process.setsid
          sleep grace_period
          Process.kill :TERM, unicorn_pid if unicorn_running?
        end
      end
    end
  end
end
