# A very simple server that always responds with the time it was started.  This
# is used in tests to check whether the server has started or restarted
time = Time.now.to_f
run lambda { |env| [200, {"Content-Type" => "text/plain"}, ["#{time}"]] }
