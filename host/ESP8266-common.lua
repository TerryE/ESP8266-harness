--[[ ESP8266-common.lua
This module contains some common routines that are used in both ESP8266-host and
ESP8266-init
]]

-- Abnormal exit ---------------------------------------------------------------
local function die( msg, rtn ) 
  if(type(rtn)=="string") then rtn = tonumber(rtn) end
  io.stderr:write( msg.."\n" )
  if isset(client) then client:close() end
  os.exit(rtn or 1)
end

-- I am a terrible mistyper so force explicit declaration of globals -----------
local function forceExplicitGlobals()
  function _G.global(var, val) rawset(_G, var, val == nil and {} or val) end
  function _G.isset(var) return rawget(_G, var) end
  setmetatable(_G, {__newindex = function (t, k, v)
      if (k:sub(1,2) ~= "__") then
        local t = debug.getinfo(1,'nl')
        local msg = "Global \"%s\" implicitly defined at %s line %u. Use global()"
        die(msg:format(k, t.namewhat, t.currentline), 2)
      end
      rawset(t, k, v or {})
    end,
    __index = function (t, k)
      if (k:sub(1,2) ~= "__") then
        local t = debug.getinfo(1,'nl')
        local msg = "Global %s is nil at %s line %u."
        print(msg:format(k, t.namewhat, t.currentline))
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

-- Use LuaSrcDiet to compress a Lua file ---------------------------------------
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

--Load a file, syntax checking and compressing if necessary --------------------
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


local M = {
  die = die,
  forceExplicitGlobals = forceExplicitGlobals,
  load_file = load_file,
  save_file = save_file,
  compress_lua = compress_lua,
  get_file = get_file,
  }

return M
