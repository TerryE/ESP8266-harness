#!/usr/bin/env lua
--[[ESP8266-host.lua
  The development and execution harness for the ESP8266 chipset boards is
  based on two application subsystems:

   * the developer machine where a simple classical *nix-style command
     interface is provided to make remote function calls as a TCP clients to
     the ESP IoT board.  For example the command "esp8266 -l" lists all files
     on the ESP-XX file system.

   * an extensible framework which is installed on the ESP-XX files which acts
     a TCP server (typically on TCP socket 8266) to receive and action these
     commands.

  Note that:

   * Both the client and server ends are both written in Lua 5.1, with the
     client end being standard Lua 5.1 and the server being written in the
     nodeMCU eLua variant.

   * These variants are identical in terms of Lua language syntax, with the
     main difference being that the ESP8266 runs a severely cut-down VM and
     runtime system suitable for embedded use.

   * The other main aspect is that memory use and execution performance aren't
     really an issue on the development side (which will typically be an Intel
     / AMD PC or Laptop, or an ARM RPi), so the main development aim was to
     keep the code simple and straightforward.  However, RAM is severely limited
     on the ESP8266 side (~23Kbyte application RAM), as is the file system, so
     a key design criteria for the harness was to keep the RPC stack simple and
     its resident footprint as small as practical.
]]

DEVICE_IP = os.getenv("ESP8266_DEVICE") or "192.168.1.48"
DEVICE_PORT = os.getenv("ESP8266_PORT") or "8266"
local MAX_BLOB_BRICK = 1024

-- For some reason the script dir isn't on the package path so add it ----------
local function add_script_dir_to_path()
  local s = arg[0]:find("[^/]+$")
  if not s then return end  -- "." is already on the path
  local path = arg[0]:sub(1,s-1)
  package.path = path.."?.lc;"..path.."?.lua;"..package.path
  return path
end
-- Now import required modules -------------------------------------------------
local sript_path = add_script_dir_to_path()
local px = require("posix")
local CM = require("ESP8266-common")
global( "CM", CM)

local AR = require("ESP8266-routines")
global( "BT", require("ESP8266-bootstrap") )

local die,    create_TCP_client,    TCPsend,     TCPreceive = 
   CM.die, CM.create_TCP_client, CM.TCPsend, CM. TCPreceive

-- low level RPC to ESP8266 ----------------------------------------------------
local function callESP8266( arg )

--[[ The RPC protocol to the ESP8266 is extremely lightweight as a key design
objective arises from the very limited RAM available on the processor: the
decode / encode logic of marshalling parameter must be kept to a minimum.  To
this end, both the request and response are a single CRLF-terminated
record, which comprises ASCII tab-separated line (TSL) fields.  This line can
be followed by an optional binary blob.

No escaping is supported in the TSL, so clearly you can't have a tab in any
parameter.  The first two request fields are mandatory
  *  the request name
  *  the size of the binary blog. This is usually zero, but if non-zero then
     the blob is appended to the line.

Not that the blob size might be negtaive and the sign is used to flag that
the blob parameter should be written to a temporary file on the ESP8266's
SPIFlash file system, rather than being maintained in memory.  This is again
because of the ESP8266's limited RAM. Also note that because the the ESP8266
Flash storage has a limited write life, use of file-based blobs should be
avoided where possible, e.g. if the blob size is <1K.

On the reply a third field is also mandatory: the response status.  This
follows the unix convention of 0 = OK, >0 an error
]]
  local blobLen = arg.blob and #(arg.blob) or 0
  local request = arg.cmd .. "\t" .. 
                  ((blobLen <= MAX_BLOB_BRICK) and blobLen or -blobLen)
  local params  = arg.params or {}
  if #params > 0 then
    request = request .. "\t" .. table.concat(params, "\t") 
  end
-- print(arg.cmd, arg.params or "")  
  if not isset("TCPclient") then
    create_TCP_client()
  end
  
  -- send out request broken into MAX_BLOB_BRICK packets if necessary
  TCPsend(request.. "\r\n")
  if blobLen > 0 then TCPsend( arg.blob) end
 
  -- listen for and process the response in TSV fields
  local line, fld = "\t"..TCPreceive(), {}

  -- split into fields and covert #2 and #3 to numeric
  for f in line:gmatch("\t([^\t]*)") do fld[#fld+1] = f end
  fld[2] = tonumber(fld[2] or 0)
  fld[3] = tonumber(fld[3] or 0)

  -- if a blob is being returned then receive it
  fld[2] = (fld[2] > 0) and TCPreceive(fld[2]) or ""
    
  -- if the response blob size is non-zero then replace it with the blob
  assert (fld[1] == arg.cmd, 
         'unexpected response '..fld[1]..' != '..arg.cmd)
  return unpack(fld,2)
end

-- main function (entry point is after this definition)
local function main()
  local arg, argn, i, error = arg, #arg, 1
  if argn == 0 then
    arg[1], argn = "-h", 1
  end

  -- handle arguments
  local i = 1
  while i <= argn do
    local option, p1, p2 = unpack(arg, i, i+2)
    local mFlag, optChar = option:sub(1,1), option:sub(2,2)

    if mFlag == "-" and #option == 2 and AR[optChar] then
      -- the action routine exists so call it
      local idx, status, msg = AR[optChar](p1, p2)
      if status > 0 then
        die(msg, status)
      end

      if (msg ~= "") then
        if msg:sub(-2) ~= CR then msg = msg .. CR end
        print (msg)
      end
      i = i + idx + 1
    else
      die ("unrecognized parameter " .. option)
    end
  end  --while
  return 0
end

--=========================== Mainline Execution =============================--

-- export some local variables to global context
global( "callESP8266",     callESP8266 )
global( "noHeaderFlag",    false )
global( "compressionFlag", false )
global( "script_path",     script_path )
global( "CR",              "\r\n" )

CM.force_explicit_globals() -- runtime so this can go here
if not main() then
  die("Please run with option -h or --help for usage information")
end

if isset("TCPclient") then
  px.close(TCPclient)
end

-- If a child server process is running, then wait until completion then exit
if isset("serverPID") then
  px.wait(serverPID)
end
