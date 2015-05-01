--[[ ESP8266-bootstrap.lua
  This module contains the bootstrap code to allow the ESP8266 Lua application
  to be reimaged from scratch.  It first attemps to do this by invoking the
  existing bootstrap hook in the existing firmware.  However if this is broken
  then it falls back to loading the bootstrap over the a virtual comm-port 
  which is hooked into the ESP8266's uart interface.  The idea is that with 
  even in the worst case, you can reload the complete application onto the 
  device with a single command from the dev PC in seconds.

  Unfortunately on downside of having to talk to the virtual comm-port is that 
  I can't do this through the core Lua 5.1 install so I need the Lua posix 
  entension, which is really just a Lua callable wrapper around the POSIX API.
  Most distros have this as an add-on.  For example on Ubuntu and Rasbian:
    >  sudo apt-get install lua-posix

  The downside of using this POSIX extension is that the documentation is poor,
  but since it is just a direct wrapper of the C liraries, the man 3 pages on
  most *nix systems, plus looking at the C wrapper source gives you all that 
  you need.
  ]]

function die(s) print(s) os.exit(1) end
function declare(k,v) _G[k]=v end

local px = require "posix"
local fds={}

--========================= USB comm port functions ==========================--

-- Set attributes of virtual TTY device on /dev/ttyUSBn ------------------------ 
local function setup_vtt(vtt,rate)
  if px.tcsetattr(vtt, 0, { cflag = rate + px.CS8 + px.CLOCAL + px.CREAD,
	    iflag = px.IGNPAR, oflag = px.OPOST, 
	    cc = {[px.VTIME] = 0, [px.VMIN] = 1}}) == -1 then
	  die( 'unable to setup virtual tty device' )
  end
end
  
-- Open first ttyUSBn device found in /dev -------------------------------------
local function open_USBdev()
  local vtt = px.glob("/dev/ttyUSB*")
  if type(vtt) ~= "table" then die "No USB virtual comm ports found." end
  vtt = vtt[1] 
  local fd, err = px.open(vtt, px.O_RDWR + px.O_NONBLOCK);
  if not fd then die("Open of "..vtt .." failed:", err) end
  setup_vtt(fd, px.B115200)
	return fd, vtt
end

-- Poll the given fd for an in event and then action it ------------------------
local function poll_fds(fds, timeout)
  --[[poll_fds takes and an arry of {[fd] = action_function, ...} and executes
    a poll across these for an input event. If an event occurs then it 
    executes the corresponding action function and returns the result.
    
    This poll is designed to work across POSIX fds, so it can be used to
    implement non-blocking I/O across a mix of tty, socket and other devices.]] 
  local fd, entry
  for fd, entry in pairs(fds) do
    if type(entry) == "function" then
      print("Adding FD"..fd.." to poll list")
      fds[fd] = { events = {IN=true}, func = entry }
    elseif type(entry) == "table" then
      if not entry.func then die ("Incorrect arguments for poll_fds")  end
      entry.events = {IN=true}
    end
  end
  if px.poll(fds, timeout) > 0 then
    for fd, entry in pairs(fds) do
      if entry.revents.IN then
        entry.revents = nil
        entry.events = {IN=true} 
        return entry.func(fd)
      end
    end
  else 
    return 0
  end
end
-- Look for the USB tty device and try to connect at 115200 then 9600
local function connect_to_ESP_via_USB()
  local vtt,USBdev,status = open_USBdev()
  if not vtt then die ("Can't connect to USB tty") end
  
  fds[vtt] = function (fd)
    resp,err = px.read(fd,100)
    if err then die ("Failure on USB tty read: "..err) end
    if resp:find("hello") then return fd end
    return -1
  end
 -- If the ESP8266 is listening at this baud this will reply "hello"
  px.write(vtt,"='hel'..'lo'\r\n")  px.sleep(2)
  for i = 1,6 do
    status = poll_fds(fds, 3000)
    if status > 0 then break end
    if i == 3 then setup_vtt(fd, px.B9600) end
  end
 return status
end

--============================== TCP functions ===============================--

-- Open a TCP listener on the specified port -----------------------------------
local function listen_on_port(port)  
  fd = px.socket(px.AF_INET, px.SOCK_STREAM , 0)
  px.setsockopt(fd, px.SOL_SOCKET,  px.SO_RCVTIMEO, 60, 0)
  if not px.bind(fd, {family=px.AF_INET, addr="0.0.0.0", port=port}) then
    print("Can't connect to socket") return
  end
  px.listen(fd,2)
  return fd
end

-- Simple TCP responder --------------------------------------------------------
local function TCPresp(fd)
  print(px.read(fd,500))
  px.write(fd,"Hello World\r\n")
  return 1
end

-- TCP connection accepter------------------------------------------------------
local function TCPaccept(fd)
  local afd, sa = px.accept(fd)
  fds[afd]=TCPresp
  print("Connection from "..sa.addr..":"..sa.port)
  return TCPresp(afd)
end

--=========================== Bootstrap functions ============================--

local function get_boot_params( classC, host_C, gateway_C, esp8266_C,
                                port, sid, pwd, secret)
-- Example params: "192.168.1", 92, 1, 48, 8266, "myWifi", "pwd", "@DQ1%"
  local boot_params = {classC..".", host_C, gateway_C, esp8266_C, sid, pwd, secret}

--[[This bootstrap is downloaded over a UART link a line at a time and executed
   in immediate mode. The last line kicks of the timer which orchestrates the
   reconfigure and reload. Note that the bootstrap lines must be short enough 
   to be buffered in the UART, and that the timer poll (funtion T)  
     * executes function W on the 1st pass to set up the Wifi and IP
     * waits for the wifi to be connected and a valid IP is confirmed
     * then stops the timer and executes function C to intiate the call-back
       connection to the host. 
   
   Once connected to the host by TCP the loader will execute any packets 
   downloaded to it so long as they are correctly signed.  These packets set
   up the file system, and The last one of these shuts down the receive loop 
   and reboots the ESP8266.
  ]]
  return { '',
  'function R(s,d) print(d) if ow.crc16(V..d) == 0 then loadsource(d)() A(s) end A(s) end',
  'function A() N=N+111 S:send(N.."\\r\\n") print("Sending "..N.." to "..X..H..":'..port..'") end', 
  'function W() print (111) wifi.setmode(1) Z.disconnect() Z.config(K,P ) Z.connect() ',
    'Z.setip({ip=X..E, netmask="255.255.255.0", gateway=X..G}) W=nil end',
  'function C() S=net.createConnection(net.TCP, 0) S:on("receive",R) S:connect('..port..',X..H)',
  'print( "Connecting to "..X..H..":8266") A() end',  
  'function T() if W then W() elseif Z.status()==5 and Z.getip() then tmr.stop(6) C() end end',
  'X,H,G,E,K,P,V,Z,N = "' .. table.concat(boot_params, '","') .. '",wifi.sta,111', 
  'tmr.alarm(6, 2000, 1, T)'
  }
end

local function USB_bootstrap_listener(vtt)
  resp,err = px.read(vtt,300)
  if err then die ("Failure on USB tty read: "..err) end
  px.write(px.STDOUT_FILENO, resp)
  if resp:find(">") then 
    bootstrap = {unpack(bootstrap,2)}
    if (#bootstrap > 0) then
--        print("Sending: "..bootstrap[1].."--> ")
      px.write(vtt, bootstrap[1].."\r\n")
      px.sleep(1)
    end
  end
end

--=========================== Bootstrap functions ============================--

declare( "bootstrap", 
  get_boot_params( "192.168.1", 91, 1, 48, 8266, 
                   "Homefarm", "in#te#sperant", "wre!?") )
                   
local vtt = connect_to_ESP_via_USB()
if vtt <= 0 then 
  die("Could not connect to ESP8288 or not responding at 11520 or 9600 baud")
end 

local tcp = listen_on_port(8266)
fds[vtt] = USB_bootstrap_listener
fds[tcp] = TCPaccept
px.write(vtt,"\r\n")  px.sleep(1)
while poll_fds(fds, 6000) ~= 0 do end


os.exit(0) 


--[[
local M = {
  get_file = get_file,
  }

return M
]]




