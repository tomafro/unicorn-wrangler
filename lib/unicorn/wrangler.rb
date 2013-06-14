require "unicorn/wrangler/version"

module Unicorn
  class Wrangler
    attr_reader :command, :pidfile, :grace_period
    attr_accessor :unicorn_pid

    def initialize(command, options = {})
      @command = command
      @pidfile = File.expand_path(options[:pidfile] || 'unicorn.pid')
      @grace_period = options[:grace_period] || 60
      @verbose = options[:verbose]
    end

    def start
      trap_signals(:HUP) { restart_unicorn }
      trap_signals(:QUIT, :INT, :TERM) do |signal|
        kill_unicorn_after_delay
        exit
      end

      if old_unicorn = old_pidfile_contents && process_running?(old_unicorn)
        signal :QUIT, old_unicorn
      end

      self.unicorn_pid = pidfile_contents

      if unicorn_pid && process_running?(unicorn_pid)
        debug "running unicorn found at #{unicorn_pid}"
        restart_unicorn
      else
        debug "no running unicorn found, starting new instance"
        self.unicorn_pid = Process.spawn(command, pgroup: true)
        wait_for { process_running?(unicorn_pid) }
        debug "new instance started with PID #{unicorn_pid}"
      end

      loop do
        unless process_running?(unicorn_pid)
          debug "unicorn(#{unicorn_pid}) no longer running, quitting."
          exit
        end
        sleep 1
      end
    end

    private

    def trap_signals(*signals, &block)
      signals.map(&:to_s).each do |signal|
        trap(signal) do
          debug "received #{signal} (managing #{unicorn_pid})"
          block.call signal
        end
      end
    end

    def restart_unicorn
      debug "restarting unicorn process at #{unicorn_pid}"
      signal "USR2", unicorn_pid
      wait_for { pidfile_contents && unicorn_pid != pidfile_contents }
      debug "new master process started at #{pidfile_contents}"
      sleep grace_period
      signal "TERM", unicorn_pid
      self.unicorn_pid = pidfile_contents
    end

    def pidfile_contents
      File.exist?(pidfile) && File.read(pidfile).to_i
    end

    def old_pidfile_contents
      File.exist?(pidfile + ".oldbin") && File.read(pidfile + ".oldbin").to_i
    end

    def signal(name, pid)
      debug "signalling #{pid} with #{name}"
      Process.kill name, pid
    rescue Errno::ESRCH
    end

    def process_running?(pid)
      pid && Process.getpgid(pid)
    rescue Errno::ESRCH
      false
    end

    def wait_for(&block)
      until block.call
        sleep 0.1
      end
    end

    def kill_unicorn_after_delay
      if process_running?(unicorn_pid)
        unless fork
          debug "preparing to kill unicorn #{unicorn_pid} in #{grace_period} seconds"
          Process.setsid
          sleep grace_period
          signal :TERM, unicorn_pid if process_running?(unicorn_pid)
        end
      end
    end

    def debug(message)
      puts message if @verbose
    end
  end
end
