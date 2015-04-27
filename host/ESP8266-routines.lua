--[[ ESP8266-routines.lua
This module contains the action routines as documented in the help text below.
All routines follow the same template with take 0-2 parameters depending on the
function and return a 3 tuple which comprises:
  *  The number parameters used (used by the caller to bump the args list)
  *  An integer return status (0 = OK)
  *  An options output message to be display, or the error message in the 
     case of a error with return status > 0
     
Note that whilst an action routine can upload blob data from the ESP8266, this
is always processed and possibly saved according to a specified parameter.
]]
-- Standard help text response  ------------------------------------------------
local function getHelp()
  return 0,0,[[
>  esp-cmd -h
Usage: esp-cmd [options] [filenames]

Example:
  >esp-cmd -i -c fred.lua -i -l

Options with no parameters:
  -i                  prints memory and version information for the ESP8266
  -h                  prints this usage information
  -l                  print file listing for ESP8266
  -b                  reformat ESP8266 and restore minimum bootstap files
  -r                  restart ESP8266 after 2s delay
  -N                  No header flag -- usually used in combination with -p
 
Options with file parameter
  -c <file>           download and compile the specified file on the ESP8266
  -d <file>           download the specified file name to the ESP8266
  -u <file>           upload the specified file name from the ESP8266

Options with two file parameters
  -m <from> <to>      move the specified file within the ESP8266 file system

Note that the specified file name may include an optional path.  This is applied
to the local file naming but is ignored for the ESP8266 filename.  So the
following example downloads /tmp/mytable.txt to mytable.txt on the ESP8266:
 
  >esp-cmd -d /tmp/mytable.txt
 
 Options with csv parameters
 
   -x cmd,params      Execute command "cmd" with parameters "params"
   -X cmd,params <file>  Execute command "cmd" with parameters "params" and
                      attach blob given in file.
]]
end

-- Get version and other info --------------------------------------------------
local function getInfo()
  local keys= {"majorVer", "minorVer", "devVer", "chipid", "flashid", 
               "flashsize", "flashmode", "flashspeed", "free heap", "GC count"}
  local ans = {callESP8266{cmd= "util", params = {"info"}}}
  if ans[2] ~= "0" then return 1, tonumber(ans[2]), ans[3] end
  ans = {unpack(ans,3)}

  -- noHeader mode is used for command scripts, e.g. declare `esp8266 -N -i`  
  local layout = noHeaderFlag and "ESP8266_%s=%s" or "%s: %s"
  for i,v in ipairs(ans) do 
    ans[i] = layout:format(keys[i], v)
  end
  return 0, 0, table.concat(ans, "\r\n")
end

-- Set No Header Mode ----------------------------------------------------------
local function setNoHeader()
  define("noHeaderFlag", true)
  return 0, 0, ""
end

-- Do a file listing of the ESP8266 --------------------------------------------
local function getFileList()
  local listing, status, resp = callESP8266{cmd="list"}

  if status ~= "0" then return 0, status, resp end
  
  local underline = ("="):rep(#resp)
  resp = noHeaderFlag and "" or resp..CR..underline..CR..CR
  
  return 0, status, resp..listing
end

-- Reboot the ESP8266 ----------------------------------------------------------
local function restart()
  local _, status, resp = callESP8266{cmd="util", params = {"restart"}}
  return 0, status, resp
end

-- Reformat and bootstrap the ESP8266 ------------------------------------------
local function bootstrap()
  -- TODO: download a new copy of the key code in a blob
  local _, status, resp = callESP8266{cmd="bootstrap"}
  return 0, status, resp
end

-- Download a file to the ESP8266 --------------------------------------------
local function download(filename)
  local s, e = filename:find("[^/]+$")
  local path, baseName, status, resp = "", filename
  
  if s and s > 1 then 
    path, baseName = filename:sub(1,s-2), filename:sub(s, e)
  end

  local fileContent = loadFile(filename)
  
  local _, status, resp = callESP8266{
      cmd="util", 
      params={"download", baseName}, 
      blob  = fileContent }
  return 1, status, noHeaderFlag and "" or resp
end

-- Print a file on the ESP8266 -------------------------------------------------
local function printFile(filename)
  local listing, header
  local listing, status, resp = callESP8266{
      cmd="util", 
      params={"upload", filename}}
  
  if status > 0 then return 0, status, resp end

  if not noHeaderFlag then 
    local underline = ("="):rep(#resp)
    resp = resp..CR..underline..CR..CR 
  end
  
  return 1, status, resp..listing
end

-- remove file(s) on the ESP8266 -----------------------------------------------
local function remove(filepattern)
  -- The input pattern can contain a subset of magic characters:
  --   ? matches any character
  --   * matches any character sequence
  -- and these are converted to a standard Lua pattern
  
  local _, v
  for _, v in pairs {{".","\\."}, {"?", "."}, {"*", ".*"}} do
    filepattern = filepattern:gsub(v[1], v[2])
  end
  
  local listing, status, resp = callESP8266{
      cmd="util", 
      params={"remove", filepattern}}
  
  if status > 0 then return 0, status, resp end

  return 1, status, noHeaderFlag and "" or resp
end

-- Upload a file from the ESP8266 ----------------------------------------------
local function upload(filename)
  local s, e = filename:find("[^/]+$")
  local path, baseName, status, resp = "", filename

  -- Note the filename can include an optional path which is ignored on the 
  -- ESP8266.  Viz the basename is not changed.  You'll need a local rename
  -- if you want to change the name locally. 
  if s and s > 1 then 
    path, baseName = filename:sub(1,s-2), filename:sub(s, e)
  end

  local content, status, resp = callESP8266{
      cmd="util", 
      params={"download", filename}}
  
  if status == 0 then
    saveFile( filename, content )
  end  
  
  return 1, status, noHeaderFlag and "" or resp
end

-- execute a command on the ESP8266 --------------------------------------------
local function execute(commandString)
  --TODO
  return 1, status, resp
end

-- execute a command on the ESP8266 with blob attached -------------------------
local function executeWithBlob(commandString, blobName)
  --TODO
  return 1, status, resp
end

local M = { 
  h = getHelp,
  i = getInfo,
  l = getFileList,
  N = setNoHeader,
  r = restart,
  R = bootstap,
  c = compileLua,
  p = printFile,
  d = download,
  u = upload,
  k = remove, --TODO
  m = rename, --TODO
  x = execute,
  X = executeWithBlob,
  }
  
return M
