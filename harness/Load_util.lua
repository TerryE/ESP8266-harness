-- Load_util.lua
--[[
This is set of short utilities that are grouped together under utility function
for convenience.  
]]

local file, node, table, tmr = file, node, table, tmr
local this, socket = unpack({...},1,2) 
local CHUNK_SIZE = 1024
local fld = this._fld
local utilFunc = fld[3]
local resp, blob

if utilFunc == "info" then

  -- majorVer, minorVer, devVer, chipid, flashid, flashsize, flashmode, flashspeed
  local a,b,c,d,e,f,g,h=node.info(); 
  local info = {a,b,c,d,e,f,g,h, node.heap(), 
               ("%d"):format(collectgarbage("count")*1024)} 
-- print(table.concat(info, "\t"))
  resp = "info\t0\t0\t" .. table.concat(info, "\t") .. "\r\n"
  info = nil

elseif utilFunc == "restart" then
  tmr.alarm(4, 5000, 0, function() node.restart() end)
  resp = "restart\t0\t0\tESP8266 restarting in 5 secs\r\n"  

-- TODO this upload might get longer than the max string length
-- PANIC: ... need <1460 payload
   
elseif utilFunc ==   "upload" then
  local filename = fld[4]
  local size = file.list()[filename]
  if size then
    file.open(filename)
    blob = file.read(size)
    file.close()
    resp = ("upload\t0\t%u\tFile %s (%u bytes)\r\n"):format(
              blob:len(), filename, size)
  else
    resp = ("upload\t1\t0\File not found\r\n")
  end

elseif utilFunc == "download" then
  local filename = fld[4]
--print("Entering download for "..filename)
  resp = ("download\t1\t0\Download failed\r\n")
  if this._tmpName then
--print("Renaming file ".. this._tmpName)
    file.remove(filename)
    if file.rename(this._tmpName, filename) then
      resp = (("download\t0\t0\tFile %s (%u bytes) created\r\n"):format(
                filename, fld[2]))
    end 
  elseif this._blob then
--print("writing blob")
    file.remove(filename)
    if file.open(filename, "w+") then
      file.write(this._blob); file.close()
      resp = (("download\t0\t0\tFile %s (%u bytes) created\r\n"):format(
                filename, fld[2]))
    end
  else
--print("ehhhhhh??")
  end 
else
  resp = ("error\t1\t0\Unknown function\r\n")
end
this._tmpName = nil
this._fld = nil
this._blob = nil  

--print (resp)

if resp then socket:send(resp) end
if blob then socket:send(blob) end
