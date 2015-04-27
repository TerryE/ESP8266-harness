--[[ example-init.lua

This stripped-down RPC framework is based on a request / response with the
device acting as the server. The key design goal with this framework is to
enable the esp8266 device to act as a IoT applicance with mimimal runtime
footprint for the framework itself.

In practice this routine is overwritten by a host configuration script which 
takes the site-specific parameters from the command line

For more on the ideas and architecture behind this approach see the 
accompanying README.md and wiki
]]  

CONFIG = {
  sid = "Homefarm",
  sid_key = "in#te#sperant",
  ip="192.168.1.48",
  netmask="255.255.255.0",
  gateway="192.168.1.254", }

uart.setup(0, 460800, 8, 0, 1, 1 )
local setup = require("Load_setup")
if setup then tmr.alarm(6, 5000, 1, setup) end
