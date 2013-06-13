# Unicorn::Wrangler

A simple process to launch and relaunch unicorn.  When launched, it either starts a new unicorn if none is running (found using the given pidfile), or restarts the existing unicorn if one is found.

Usage:

unicorn-wrangler --pidfile /path/to/unicorn.pid --startup-time 60 -- /path/to/unicorn <unicorn-options>
