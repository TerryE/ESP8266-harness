-- Load_setupWifi.lua
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
local c, stn = CONFIG, wifi.sta
if (c) then
  ---- First Pass: Setup the Load table and configure the network ----
  print("Configuring network")

  wifi.setmode(wifi.STATION)
  stn.disconnect()
  stn.config(c.sid, c.sid_key)
  stn.connect()
  stn.setip({ip=c.ip, netmask=c.netmask, gateway=c.gateway})

  Load = setmetatable( 
    {ip = c.ip,
     receiver = function(sk, rec)
       local load = Load
       collectgarbage()
       local cmd = load:processCmd(rec)
       if not cmd then return end
       return Load[cmd](load,sk) -- do a tailcall to remove call frane
     end,
    },
    {__index = function (this,key)   
       if key:sub(1,1)=='_' then return nil end
       key="Load_" .. key
       local rtn, error = loadfile(key .. ".lc")
       if error and error:sub(1,11) == "cannot open" then
         rtn, error = loadfile(key .. ".lua")
       end
       if not error then 
         print(type(rtn).." "..key.." loaded")
         return rtn 
       end
       -- if neither files exist then assume that this is a value
       if error:sub(1,11) ~= "cannot open" then
         print(key .. " - " .. error)
       --return nil    (this is the default anyway)
       end
     end} )

  CONFIG = nil
  
else
  ---- Second Pass: Clear down the timer alarm and set up the Listener.  ----
  local l=Load
  print("Starting Listener")
  tmr.stop(6); tmr.alarm(6, 5000, 0, print); tmr.stop(6)
  if not l then return end
  l.srv=net.createServer(net.TCP)
  l.srv:listen(8266, function(socket) socket:on("receive",l.receiver) end)
  print("Listening on " .. stn.getip() .. ":8266") 

--[[ At this point the timer even handler exits and the GC collects all of the
now disused chunks, so only those associated with Load remain ]]

end
