# Unicorn::Wrangler

A simple process to launch and relaunch unicorn.  When launched, it either starts a new unicorn if none is running (found using the given pidfile), or restarts the existing unicorn if one is found.

Usage:

unicorn-wrangler --pidfile /path/to/unicorn.pid --startup-time 60 -- /path/to/unicorn <unicorn-options>

When the wrangler starts, it does the following:

If unicorn is not running (determined by looking for the unicorn pidfile, and if it exists, checking the named process is running), it starts unicorn with the given command.

If unicorn is running, it reloads the running instance, then terminates the old instance after the grace period has passed.

The wrangler will continue to run while the monitored unicorn process runs.  It will stop running shortly after unicorn stops.

If the wrangler is manually stopped (by sending INT or TERM signals to its process), it forks a new 'assassin' process that will terminate unicorn after the grace period has passed.  This is so that quickly stopping and starting the wrangler will have the effect of reloading unicorn, not terminating and restarting it.

Do not confuse with [unicorn_wrangler](https://github.com/grosser/unicorn_wrangler)
