#!/usr/bin/env lua

local socket = require("socket")
local DEVICE_IP = os.getenv("ESP8266_DEVICE") or "192.168.1.48"
local DEVICE_PORT = os.getenv("ESP8266_PORT") or "8266"

local action = require("ESP8266-routines")

local function die( msg, rtn ) -- Abnormal exit --------------------------------
  io.stderr:write( msg )
  if client then client:close() end
  os.exit(rtn or 1)
end

do -- I am a terrible mistyper so force explicit declaration of globals --------
  function define(var, val) rawset(_G, var, val) end
  
  local mt_G = getmetatable(_G) or {}
  mt_G.__newindex = function (t, k, v)
    if (k:sub(1,2) ~= "__") then
      die("Global ".. k .. "implicitly defined. Use define()", 2)
    end
    rawset(t, k, v or {})
  end
end

local client = socket.connect( DEVICE_IP, 8266 ) or 
                  die("Unable to connect to "..DEVICE_IP..":"..DEVICE_PORT)
client:setoption( 'keepalive', true )
client:setoption( 'tcp-nodelay', true )

define( "CR", "\r\n" )

--------------------------------------------------------------------------------
--                        Low level glue routines                             --
--------------------------------------------------------------------------------

-- Basic TCP send with error handling wrapped in -------------------------------
local function TCPsend( buf )
--print ("Sending ... " .. buf)
  local n, error, nSent = client:send(buf)
  if error then 
    die( "Error sending TCP packet to ESP8266: " .. 
          error .. " (" .. nSent .. "bytes sent out of " .. n)
  end       
end

-- Basic TCP receive with error handling wrapped in ----------------------------
local function TCPreceive( limit )
  local limit = limit or "*l"
  local buf, error, part = client:receive( limit )  
-- print("Receiving: "..buf)
  if error then 
    die (string.format(
      "Error receiving TCP packet from ESP8266 (%u bytes received %s): %s",
      #part,
      (limit == "*l") and "with no EOL" 
                       or ("out of ".. limit .." bytes expected"),
      error))
  end
  return buf 
end

-- Low level RPC to ESP8266 ----------------------------------------------------
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
follows the unix convention of 0 = OK, >0 an error ]]

  local MAX_RAM_BLOB = 1024
  local blobLen = arg.blob and #(arg.blob) or 0 
  local s = (blobLen > MAX_RAM_BLOB) and -blobLen or blobLen
  local request = arg.cmd .. 
                  ((#(arg.parmeters) == 0) 
                     and "" 
                     or  "\t" .. table.concat(arg.params, "\t"))
  -- send out request
  TCPsend(request)
  if blobLen > 0 then 
    for s = 1, blobLen, MAX_RAM_BLOB do 
      local e = s + MAX_RAM_BLOB
      if e > blobLen then e = blobLen end
      TCPsend(arg.blob:sub(s,e))
    end
  end
  
  -- listen for and process the response in TSV fields
  local line, fld = "\t"..TCPreceive(), {}
  line:gsub("\t[^\t]*", function(f) fld[#fld+1] = f:sub(2,-1) end)
  --TODO: accept multiblock blob
  -- if the response blob size is non-zero then replace it with the blob
  fld[3] = (tonumber(fld[3]) == 0) and "" or TCPreceive(tonumber(fld[3]))
  return unpack(fld)
end

-- Wrappers for RPC to ESP8266 without and with attached blob ------------------
local function remoteCall(...)
  local arg = {...}
  local cmd = arg[1]
  return callESP8266{ cmd = cmd, params={unpack(arg, 2)}}
end
--TODO: work out why this doesn't compile !!!!!
local function remoteCallBlob(...)
  local cmd = ...
  local nArg = select('#', ...)
  local blob = unpack( {...}, nArg)
  local params = {unpack( {...}, 2, nArg-1)}
  return callESP8266{ cmd = cmd, params = params, blob = blob } 

end
-- Load contents of the given file ---------------------------------------------
local function loadFile(fname)
  local INF = io.open(fname, "rb") or 
                die('cannot open "'..fname..'" for reading')
  local dat = INF:read("*a") or
                die('cannot read from "'..fname..'"')
  INF:close()
  return dat
end

-- Save contents to the given file ---------------------------------------------
local function saveFile(fname, dat)
  local OUTF = io.open(fname, "wb") or
                 die('cannot open "'..fname..'" for writing')
  local status = OUTF:write(dat) or 
                 die('cannot write to "'..fname..'"')
  OUTF:close()
end
--------------------------------------------------------------------------------
--        main function (entry point is after this definition)                --
--------------------------------------------------------------------------------
local function main()
  local arg, argn, i, error = arg, #arg, 1
  if argn == 0 then
    arg[1], argn = "-h", 1
  end
   
  -- handle arguments
  local i = 0
  while i <= argn do
    local option, p1, p2 = unpack(arg, i, i+2)
    local mFlag, optChar = option:sub(1,1), option:sub(2,2)
    
    if mFlag == "-" and #option == 2 and action[optChar] then
      -- the action routine exists so call it
      local status, msg, idx = action[optChar](p1, p2)

      if status ~= 0 then
        die(msg, status)
      end  
       
      if (msg ~= "") then
        if msg:sub(-2) ~= CR then msg = msg .. CR end
        print (msg)
      end
      
      i = i + idx
    else
      die ("unrecognized parameter " .. option) 
    end
    i = i + 1
  end  --while
end

-- export some local variables to global context
define( "callESP8266",  callESP8266 )
define( "client",       client )
define( "die",          die )
define( "loadFile",     loadFile )
define( "saveFile",     saveFile )
define( "noHeaderFlag", false )

-- entry point -> main() -> do_files()
if not main() then
  die("Please run with option -h or --help for usage information")
end

client:close()
-- end of script
