-- Load_setup.lua
--[[
This function configures the ESP 8266 for the specific network and sets up
the network listener.  If is called by a repeat tmr.alarm that has been 
initated by init.lua.  The repeats are:

1) (CONFIG exists) Setup the Load table, configure the network and delete
   the CONFIG.

2) Set up the Listener. Stop and clear down the timer alarm.

Note that once this routine exits, only the global Load is left with its
static routines and ip property.  The garbage collector will collect 
everything else.
]]

return function()  
  local c, stn = CONFIG, wifi.sta
  if (c) then
    ---- First Pass: Setup the Load table and configure the network ----
    print("Configuring network")

    wifi.setmode(wifi.STATION)
    stn.disconnect()
    stn.config(c.sid, c.sid_key)
    stn.connect()
    stn.setip({ip=c.ip, netmask=c.netmask, gateway=c.gateway})

    package.loaded.Load_setup = nil -- make routine effemeral

    function Receiver(sk, rec)
-- print("Processing "..rec)
      local load = Load
      collectgarbage()
      local cmd = load:processCmd(rec)
      if not cmd then return end
      return load[cmd](load,sk) -- do a tailcall to remove call frane
    end

    Load = setmetatable( 
      {ip = c.ip, name= "Load"},
      {__index = function (this,key)   
           if key:sub(1,1)=='_' then return nil end
           return require(this.name.."_"..key)
         end
       })

    CONFIG = nil
    
  else
    ---- Second Pass: Clear down the timer alarm and set up the Listener.  ----
    local l=Load
    print("Starting Listener")
    tmr.stop(6); tmr.alarm(6, 5000, 0, print); tmr.stop(6)
    if not l then return end
    l.srv=net.createServer(net.TCP)
    l.srv:listen(8266, function(socket) socket:on("receive", Receiver) end)
    print("Listening on " .. stn.getip() .. ":8266") 

  --[[ At this point the timer even handler exits and the GC collects all of the
  now disused chunks, so only those associated with Load remain ]]

  end
end
