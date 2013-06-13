require 'curl'

describe Unicorn::Wrangler do
  def wrangler_path
    Bundler.bin_path + 'unicorn-wrangler'
  end

  def unicorn_path
    Bundler.bin_path + 'unicorn'
  end

  def unicorn_cmd
    "#{unicorn_path} -p 7516 -c spec/support/unicorn.conf.rb spec/support/config.ru"
  end

  def start_unicorn
    Process.spawn unicorn_cmd
    sleep 1
  end

  def start_wrangler
    @wrangler_pid = Process.spawn "#{wrangler_path} --startup-time 1 -p spec/support/unicorn.pid -- #{unicorn_cmd}"
    sleep 1
  end

  def unicorn_pid
    File.exist?('spec/support/unicorn.pid') && File.read('spec/support/unicorn.pid').to_i
  end

  def unicorn_running?
    unicorn_pid && Process.getpgid(unicorn_pid)
  rescue Errno::ESRCH
    false
  end

  def wrangler_running?
    @wrangler_pid && Process.getpgid(@wrangler_pid)
  rescue Errno::ESRCH
    false
  end

  def cleanup_processes
    `kill -TERM #{unicorn_pid}` if unicorn_pid
    `kill -TERM #{@wrangler_pid}` if @wrangler_pid
    sleep 1
  end

  def perform_request
    Curl::Easy.perform('http://localhost:7516').body_str
  end

  context 'in general' do
    before :each do
      start_wrangler
    end

    it 'quits (but leaves unicorn running) on receiving QUIT signal' do
      Process.kill 'QUIT', @wrangler_pid
      sleep 1
      wrangler_running?.should_not be_true
      unicorn_running?.should be_true
    end

    it 'quits (but leaves unicorn running) on receiving TERM signal' do
      Process.kill 'TERM', @wrangler_pid
      sleep 1
      wrangler_running?.should_not be_true
      unicorn_running?.should be_true
    end

    it 'quits (but leaves unicorn running) on receiving INT signal' do
      Process.kill 'INT', @wrangler_pid
      sleep 1
      wrangler_running?.should_not be_true
      unicorn_running?.should be_true
    end

    it 'quits if monitored unicorn process quits' do
      Process.kill 'TERM', unicorn_pid
      sleep 3
      wrangler_running?.should_not be_true
    end

    it 'continues running after launch (so that process monitoring tools do not restart it)' do
      sleep 3
      wrangler_running?.should be_true
    end
  end

  context 'when unicorn is not running' do
    it 'launches unicorn on startup' do
      start_wrangler
      unicorn_running?.should be_true
    end

    it 'launches unicorn with a new process group (so upstart does not clean it up)' do
      start_wrangler
      Process.getpgid(@wrangler_pid).should_not eql(Process.getpgid(unicorn_pid))
    end
  end

  context 'when unicorn is already running' do
    before :each do
      start_unicorn
    end

    it 'restarts unicorn on startup' do
      original_pid = unicorn_pid
      start_wrangler
      sleep 3
      unicorn_pid.should_not eql(original_pid)
    end

    it 'continues serving requests from both unicorns startup period' do
      start_wrangler
      100.times.map { perform_request }.uniq.size.should eql(2)
    end

    it 'stops serving requests from original unicorn' do
      original_response = perform_request
      start_wrangler
      sleep 3
      perform_request.should_not eql(original_response)
    end
  end

  before :each do
    cleanup_processes
  end

  after :each do
    cleanup_processes
  end
end
