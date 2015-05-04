--[[ ESP8266-bootstrap.lua

  This module implements the host-side of the bootstrap process used to 
  load a clean version of the application to the FlashFS.  The core component 
  of the harness on the ESP8266 is a file "boot/strap.lua", the code of which 
  is defined below in the bootstrap_source variable.
  
  Once activated on the ESP8266, this loader will repeatedly call back to a 
  listener (in this script) to fetch the components to be loaded to the file
  system.  The last of these initiates a reboot to transfer control to the newly
  refreshed application.  
  
  There are three options for the developer to initiate the bootstrap:
   A) The command harness includes a boot option (-B) which invokes it.
   B) If a tool such as ESPlorer is attached to ESP8266 via its UART, the
      developer can simply execute a "require 'boot/strap'". 
   C) This script can also directly connect to the UART and download a new copy
      of the bootstrap and then invoke it.  (This is also the standard method 
      of doing a "first time" configuration of the ESP8266.)
  
  Clearly method (A) is the easiest method if the core modules of the ESP8266
  harness are OK and functioning, as this doesn't require a UART connection
  and can be executed in seconds.  However even if the Flash FS is corrupted or 
  on first load, then even method (C) takes under a minute to reload the 
  application.
  
  The bootstrap module has been designed to be minimalist -- that is small and
  with no dependecies on other modules on the ESP8266.  It can completely 
  rebuild the application, once invoked-- as long as a code server process is 
  up and listening.
  
  The boot/strap is configured to an individual chip by a set of commandline 
  parameters, e.g.
    SSID,SSIDpwd,8266,secre,91,192.168.1,48,1
    
  which are copied into the following global variables (see below) to drive the 
  configuration.  Note that the last 3 parameters may be omitted, in which
  case DHCP is use to allocated these.
    
  Also a programming note: an unfortunate downside of having to talk to the 
  virtual comm-port is that I can't do this through the core Lua 5.1 install 
  so I need to use the Lua POSIX entension, which is really just a Lua callable
  wrapper around the POSIX API.  Most distros have this as an add-on.  For 
  example on Ubuntu and Rasbian:
    >  sudo apt-get install lua-posix

  Also note that the "signing" is an integrity issue only.  It is based on a 
  crc16 and therefore has no cryptographic strength, per se.
  
  The documentation for this POSIX extension is poor, but since it is just a
  direct wrapper of the C liraries, the man 3 pages on most *nix systems, plus
  looking at the C wrapper source gives you all that you need.  
  ]]

local px = require "posix"
local function generateBootstrap(param_string)

--[[Global variable used in the bootstrap
    S  The network SSID
    F  The network SSID passphrase
    P  The port used by the ESP8266 (e.g. in this case 8266 = 192.168.1.48:8266)
    V  A "secret" used to valdate downloaded code.
    L  The sub-address of the listener server (e.g. in this case 91 = 192.168.1.91)
    C  The class C address for this network (e.g. 192.168.1)
    E  The sub-address of the ESP8266 (e.g. in this case 48 = 192.168.1.48)
    G  The sub-address of the gateway (e.g. in this case 1 = 192.168.1.1)
    
  Note that the last three can be omitted in which case DHCP is used and L must 
  be the full IP address of the listener
--]]
  local bootstrap_source = [==[
S,F,P,V,L,E,G,C = unpack(A)  B,Z,N = "Boot:",wifi,1
function fR(s,d) print(d) if ow.crc16(V..d) == 0 then loadsource(d)() fA(s) end end
function fA() N=N+1 I:send(B..N.."\r\n") print("Sending "..B..N.." to "..L..":"..P) end
function fW() print (B..N) wifi.setmode(1) Z.disconnect() Z.config(S,Fl ) Z.connect() 
  if E then Z.setip({ip=C..E, netmask="255.255.255.0", gateway=C..G}) L=C..L end fW=nil end
function fC() I=net.createConnection(net.TCP, 0) I:on("receive",fR) I:connect(P,L)
print( "Connecting to "..L..":"..P) fA() end
function fT() if fW then fW() elseif Z.status()==5 and Z.getip() then tmr.stop(6) fC() end end
tmr.alarm(6, 3000, 1, fT)
]==]

  params = {}
  for p in param_string:gsmatch("[^,]+") do
    params[#params+1] = tostring(p) or p:format("%q")
  end
  return "A="..table.concat(params,",").."\n"..bootstrap_source
end  

--=========================== Socket poll function ===========================--

-- Poll the given fd for an in event and then action it ------------------------
local function poll_fds(fds, timeout)
  --[[poll_fds takes and an arry of {[fd] = action_function, ...} and executes
    a poll across these for an input event. If an event occurs then it 
    executes the corresponding action function and returns the result.
    
    This poll is designed to work across POSIX fds, so it can be used to
    implement non-blocking I/O across a mix of tty, socket and other devices.]] 

  for fd, entry in pairs(fds) do
    if type(entry) == "function" then
--    print("Adding FD"..fd.." to poll list")
      fds[fd] = { events = {IN=true}, func = entry }
    elseif type(entry) == "table" then
      assert (entry.func, "Incorrect arguments for poll_fds")
      entry.events = {IN=true}
    end
  end

  if px.poll(fds, timeout) > 0 then
    for fd, entry in pairs(fds) do
      if entry.revents.IN then
        entry.revents, entry.events = nil, {IN=true} 
        return entry.func(fd)
      end
    end
  else 
    return 0
  end
end

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

-- Look for the USB tty device and try to connect at 115200 then 9600
local function connect_to_ESP_via_USB()
  local vtt,USBdev,status = open_USBdev()
  if not vtt then die ("Can't connect to USB tty") end

 -- If the ESP8266 is listening at this baud this will reply "hello"
  px.write(vtt,"='hel'..'lo'\r\n")  px.sleep(2)
  for i = 1, 4 do
    status = poll_fds({[vtt] = function(fd)
        resp,err = px.read(fd,100)
        if err then die ("Failure on USB tty read: "..err) end
        if resp:find("hello") then return fd end
        return -1
      end},
      3000)
    if status > 0 then break end
    if i == 2 then setup_vtt(fd, px.B9600) end
  end
  return status
end

--=========================== Bootstrap functions ============================--

local function write_bootstap_over_USB(param_string)
  local param = {}
  for p in param_string:gsmatch("[^,]+") do
    param[#param+1] = p
  end
  
  local heading = {
    "Network SSID",
    "SSID passphrase",
    "Port used by the ESP8266",
    '"Secret" for code valdation',
    "sub-address of the listener server",
    "Class C address for network",
    "The sub-address of the ESP8266",
    "The sub-address of the gateway",}
    
  if #params > #headings then die "Invalid bootstap parameters" end 
    
  for i=1,#params do
    print( ("%36s%s"):format( heading[i]..":", param[i] ) )
  end
  
  print()
  
  -- Note that loadstring is used so that even if the write fails, the 
  -- bootstrap is still executed.
  local bootsource = "B=[==["..generateBootstrap(param_string)..
    "]==] F='boot/strap.lua' file.remove(F) file.open(F, 'w+') file.write(B) file.close()\n" ..
    "loadstring(B)()\n"
  local bootstrap={""}
  for l in bootsource:gsmatch("(.*)\n") do bootstrape[#bootstrap+1] = l end

  local vtt = connect_to_ESP_via_USB()
  if vtt <= 0 then 
    die("Could not connect to ESP8288 or not responding at 11520 or 9600 baud")
  end 

  local fds = {[vtt] = function(vtt)
      resp,err = px.read(vtt,300)
      if err then die ("Failure on USB tty read: "..err) end
      px.write(px.STDOUT_FILENO, resp)
      if resp:find(">") then 
        bootstrap = {unpack(bootstrap,2)}
        if (#bootstrap == 0) then return end
    --        print("Sending: "..bootstrap[1].."--> ")
        px.write(vtt, bootstrap[1].."\r\n")  px.sleep(1)
      end
    end}

  px.write(vtt,"\r\n")
  while poll_fds(fds, 6000) ~= 0 do end

  return 1, 0, "Bootstap initiated."
end

--======================== TCP Boot Listener/ server =========================--

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

local M = {
  write_bootstap_over_USB = write_bootstap_over_USB,
  listen_on_port = listen_on_port,
 }

return M




