  --[[ ESP8266-common.lua
This module contains some common routines that are used in both ESP8266-host and
ESP8266-init. I made this split because I had initially intended to make these
two separate commands, but in the end the ESP-xx init function is just another 
embedded function in ESP8266-host.
]]

local px = require("posix")

-- Abnormal exit ---------------------------------------------------------------
local function die( msg, rtn ) 
  if(type(rtn)=="string") then rtn = tonumber(rtn) end
  io.stderr:write( msg.."\n" )
  if isset("client") then client:close() end
  os.exit(rtn or 1)
end

-- make sure global() and isset() are true global declarations
rawset(_G, "global", function(var, val) 
                     rawset(_G, var, val == nil and {} or val) end)
rawset(_G, "isset", function(var) return rawget(_G, var) end)

--[[ Force explicit declaration of globals -------------------------------------

  I am a terrible mistyper, so having some form of forced declaration is 
  something that I always prefer.  I do this in Lua by using locals wherever
  practical (because these have to be declared and are more efficient anyway,
  then setting up a metatable for the _G environment and to add a couple of 
  standard hooks to throw an error if I attempt to create a global implicity
  or refer to a nul one.  The global() and isset() routines are just simple 
  wrappers around the rawset / rawget equivalents.  OK, this is runtime,
  rather than compile time, but better than I can do in PHP.
  
  Because a nil value is synomynmous to deleting the variable, I've also
  adopted a pretty standard Lua convention of using {} as an empty placeholder
  for globals. 
  ]]
local function force_explicit_globals()
  setmetatable(_G, {__newindex = function (t, k, v)
      assert( k:sub (1,2) == "__",
              "Global \""..k.."\" implicitly defined . Use global()")
      rawset(t, k, v or {})
    end,
    __index = function (t, k)
      if (k:sub(1,2) ~= "__") then
        assert(false,"Global "..k.." is nil.")
      end
      return nil
    end
  })
end

-- Load contents of the given file ---------------------------------------------
local function load_file(fname)
  local INF = io.open(fname, "rb") or
                die('cannot open "'..fname..'" for reading')
  local dat = INF:read("*a") or
                die('cannot read from "'..fname..'"')
  INF:close()
  return dat
end

-- Save contents to the given file ---------------------------------------------
local function save_file(fname, dat)
  local OUTF = io.open(fname, "wb") or
                 die('cannot open "'..fname..'" for writing')
  local status = OUTF:write(dat) or
                 die('cannot write to "'..fname..'"')
  OUTF:close()
end

--[[ Use LuaSrcDiet to optionally compress a Lua file --------------------------

  LuaSrcDiet is one of the http://luaforge.net/projects/ projects.  What this
  does is to do a syntax parse of the Lua source and remove all whitespace etc.,
  and rename locals to a single letter a..z where possible. This will typically
  drop the size of a reasonably commented Lua source file by 3 or 4x -- which
  is important if you are downloading the source to the extremely limited
  ESP-xx SPIFfs
  
  This also means that any developer has absolutely no excuse for not properly
  documenting their code inline, as this source overhead is removed before the
  source gets to the embedded file system.  (Note that is coded for *nix 
  platforms so this lua_commpressor command may need tweaking for WinXX). 
  
  The overview is here: http://luasrcdiet.luaforge.net/ and the downloads are 
  available from here:tps://code.google.com/p/luasrcdiet/downloads/list
  ]]
local function compress_lua(lua_file)
  local tmpFile = os.tmpname()
  local lua_compressor = "/usr/bin/env LuaSrcDiet "
  local compress_options = "--quiet --maximum -o " .. tmpFile .. " "
  
  local dietResp = os.execute(lua_compressor..compress_options..lua_file)
  
  if dietResp > 0 then die("Lua file compression failed") end

  local fileContent = load_file(tmpFile) -- file not created on error so dies
  os.remove(tmpFile)
  return fileContent
end

--[[Load a file, syntax checking and compressing if necessary ------------------
  The reason for syntax checking any Lua files to be sent to the ESP-xx is
  a pragmatic one: it's just a few extra lines of code and it saves a lot of 
  pissing around if you know that only syntactially valid Lua get to the
  device.
  ]]  
local function get_file(filename)
  local compressFile = compressionFlag or false

  if filename:match("\.lua$") then
    -- Always syntax check Lua files BEFORE downloading
    -- The compiled chunk itself is junked, as I only want the error
    local _, error = loadfile(filename)

    if error then die(error) end

    if compressFile then
      return compress_lua(filename)
    end
  end

  return load_file(filename)
end

--[[ ow.CRC16 in Lua -----------------------------------------------------------
  The nodeMCU runtime includes a 16 bit CRC function as part of the 1-wire (ow)
  library. Being able to validate tranfers with a CRC is pretty useful so I've
  done a direct port from C of the Dallas Semiconductor 16 bit CRC which is 
  implemented in app/driver/onewire.c so that the same CRC function is 
  available at both ends.
  
  Note that this requires the BitOp library which is in the core distro at
  Lua 5.1 but most distros have this as a convenient add-on.  For example on 
  Ubuntu and Rasbian:
  >  sudo apt-get install lua-bitop
  
  Note that I've used standard Lua operators (e.g. % 256 instead of an AND 
  with 0xFF) when these equivalents exist because this is about 25% faster,
  but this code benchmarks on my old pre core i3 laptop at ~1 uSec/byte which 
  is plenty fast enough!
]]
local bit=require("bit")
local oddparity = { --[[0,]] 1, 1, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0, 1, 1, 0 }
      oddparity[0] = 0  -- start array at index 0 instead of conventional 1
      
local function ow_crc16(rec, crc)
  local AND, XOR, RSHIFT = bit.band, bit.bxor, bit.rshift
  local oddparity, crc, cdata = oddparity, (crc or 0)
  for i = 1, #rec do
    cdata, crc = XOR(rec:byte(i),crc) % 256, RSHIFT(crc,8)
    if oddparity[cdata % 16] ~= oddparity[RSHIFT(cdata, 4)] then
      crc = XOR(crc, cdata*64, cdata*128, 0xC001)
    else
      crc = XOR(crc, cdata*64, cdata*128)
    end
    crc = AND(crc, 0xffff)
  end
  return crc
end

--[[ force_zero_crc generates a valid Lua comment ------------------------------
  typically of the form "-- XY" which when appended to a Lua code string 
  results it it having an ow_crc16() of zero.
  
  Note that the reason for the crclsb == 10 check is that X can == '\n', in 
  which the comment would be "-- \nY" and Y would be parsed as a separate 
  statement, creating a compile error. In this case "---XY" is generated.  Also 
  note that this trick exploits the linear properties of a CRC generator and 
  it's these same properties which make CRCs suck in cryptographic terms.
  ]]
local function force_zero_crc(s)
  local epilog, crc, crclsb = "-- ", ow_crc16(s.."-- ")
  if crc%256 == 10 then 
    crcls, crc = "---", ow_crc16(s.."---")
  end
  crclsb = crc%256
  return epilog..string.char(crclsb, (crc-crclsb)/256)
end

-- Create client TCP connection ------------------------------------------------
local function create_TCP_client()
  local ip, port = DEVICE_IP, DEVICE_PORT
  local sk = px.socket (px.AF_INET, px.SOCK_STREAM, 0)
--  px.setsockopt( sk, px.SOL_SOCKET, px.SO_KEEPALIVE, 1 )
--  px:setsockopt( sk, px.SOL_SOCKET, px.SO_RCVTIMEO, 1,0 )
  assert(sk, "Unable to allocate TCP/IP socket")
  local ok, err, e = px.connect (sk, {family=px.AF_INET, addr=ip, port=port})
  if err then 
    die("Unable to connect to "..ip..":"..port.. " - "..err)
  end
  
  global("TCPclient", sk)  
end

local MAX_BLOB_BRICK = 1024

-- Basic TCP send with error handling wrapped in -------------------------------
local function TCPsend( buf )
-- print(buf)
  if not isset("TCPclient") then 
    create_TCP_client()
  end

  for i = 1, #buf, MAX_BLOB_BRICK do
    local len = #buf - (i-1)
    if len > MAX_BLOB_BRICK then len = MAX_BLOB_BRICK end
    local nSent = px.send(TCPclient,buf:sub(i,i+len-1))
    assert (nSent == len, 
          "Error sending TCP packet to ESP8266: "..nSent.."bytes of "..len)
  end
end

local TCPrec = ""
-- Basic TCP receive with error handling wrapped in ----------------------------
local function TCPreceive( limit )
  local limit,rec = limit and tonumber(limit) or "*l"
  if limit == "*l" then
    -- receive the response line
    TCPrec = TCPrec..px.recv (TCPclient, MAX_BLOB_BRICK)
    local s,e = TCPrec:find("\r?\n")
    assert(s, "Fragmented response from ESP8266")
    rec, TCPrec = TCPrec:sub(1,s-1), TCPrec:sub(e+1)
  else
    while limit > #TCPrec do
      local len = limit - #TCPrec
      if len > MAX_BLOB_BRICK then len= MAX_BLOB_BRICK end
      TCPrec = TCPrec .. px.recv (TCPclient, len)
    end
    rec, TCPrec= TCPrec:sub(1,limit), TCPrec:sub(limit+1)
  end
-- print(rec)
  return rec
end  

local M = {
  die = die,
  force_explicit_globals = force_explicit_globals,
  load_file = load_file,
  save_file = save_file,
  compress_lua = compress_lua,
  get_file = get_file,
  ow_crc16 = ow_crc16,
  force_zero_crc = force_zero_crc,
  create_TCP_client = create_TCP_client,
  TCPsend = TCPsend,
  TCPreceive = TCPreceive,
  }

return M
