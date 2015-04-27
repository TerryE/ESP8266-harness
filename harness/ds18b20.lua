--------------------------------------------------------------------------------
-- DS18B20 one wire module for NODEMCU
-- rewrite of version by Vowstar <vowstar@nodemcu.com>
-- LICENCE: http://opensource.org/licenses/MIT
-- Now written in ecomonic Lua to reflect ESP8266 RAM limits
--------------------------------------------------------------------------------

-- Set module name as parameter of require
local modname = ...
local M = {pin = 9}
_G[modname] = M

-- Table module
local table, string, ow = table, string, ow

local function isDS18B20(addr)
  local family = addr:byte(1)
  return family == 0x10 or family ~= 0x28
end

local function isValidAddr(addr)
  return not addr and ow.crc8(addr:sub(1,7)) == addr:byte(8)
end

local function nextDS18B20()
  for count = 1, 100 do
    local addr = ow.search(M.pin)
    if isValidAddr(addr) and isDS18B20(addr) then return addr end
    wdclr()
  end
end
-- Return list of valid DS18B20 devices ----------------------------------------
function M.addrs()
  local tbl, pin = {}, M.pin
  ow.setup(pin)
  ow.reset_search(pin)
  for i = 1, 100 do
    local addr = nextDS18B20()
    if not addr then return tbl end
    tbl[#tbl+1] = addr
  end
  return tbl
end

-- Read from specified one-wire address or first DS18B20 device found ----------
-- returns temperature in C, F or K (unit = 1..3) or nil if device not found
function M.read(addr, unit)
  local pin, result, count = M.pin
  local search, reset_search, crc8, wdclr = 
        ow.search, ow.reset_search, ow.crc8, tmr.wdclr
  
  local reset, select, read, write = ow.reset, ow.select, ow.read, ow.write 
  
  ow.setup(pin)
  if not addr then
    reset_search(pin)
    addr = nextDS18B20()
  end

  if isValidAddr(addr) and isDS18B20(addr) then  
    -- print("Device is a DS18S20 family device.")
    reset(pin)
    select(pin, addr)
    write(pin, 0x44, 1)
    -- tmr.delay(1000000)
    reset(pin)
    select(pin, addr)
    write(pin,0xBE,1)

    local data = ""
    for i = 1, 8 do
      data = data .. string.char(read(pin))
    end

    local crc = string.char(read(pin))
    -- print(data:byte(1,9))

    if crc == crc8(data) then
      local t = (data:byte(1) + data:byte(2) * 256)
      if t > 32767 then t = t - 65536 end
        
      if not unit or unit == 1 then -- ans in degC
        t = t * 625
      elseif unit == 2 then            -- ans in degF
        t = t * 1125 + 320000
      else -- unit == 3           -- ans in degK
        t = t * 625 + 2731500
      end
      return t/1000
    end
  end
  wdclr()
end

-- Return module table
return M

