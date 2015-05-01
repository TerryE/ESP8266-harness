-- Load_util.lua
--[[
This is set of short utilities that are grouped together under utility function
for convenience.
]]
return function(this, socket)
  local file, node, table, tmr = file, node, table, tmr
  local CHUNK_SIZE = 1024
  local fld = this._fld
  local size, utilFunc = fld[2], fld[3]
  local resp, blob

  package.loaded.Load_util=nil -- make routine effemeral

  if utilFunc == "info" then

    -- majorVer, minorVer, devVer, chipid, flashid, flashsize, flashmode, flashspeed
    local a,b,c,d,e,f,g,h=node.info();
    local info = {a,b,c,d,e,f,g,h, node.heap(),
                 ("%d"):format(collectgarbage("count")*1024)}
    resp = "util\t0\t0\t" .. table.concat(info, "\t") .. "\r\n"
    info = nil

  elseif utilFunc == "restart" then
    tmr.alarm(4, 5000, 0, function() node.restart() end)
    resp = "util\t0\t0\tESP8266 restarting in 5 secs\r\n"

  -- TODO this upload might get longer than the max string length
  -- PANIC: ... need <1460 payload
  elseif utilFunc ==   "upload" then
    local filename = fld[4]
    local size = file.list()[filename]
    if size then
      file.open(filename)
      blob = file.read(size)
      file.close()
      resp = ("util\t%u\t0\tFile %s (%u bytes)\r\n"):format(
                blob:len(), filename, size)
    else
      resp = ("util\t0\t1\tFile not found\r\n")
    end

  else
    resp = ("util\t0\t1\tUnknown function\r\n")
  end
  this._tmpName = nil
  this._fld = nil
  this._blob = nil

-- print( resp, (blob or ""):sub(20), #(blob or ""))
  if blob then resp=resp..blob end
  if resp then socket:send(resp) end
end
