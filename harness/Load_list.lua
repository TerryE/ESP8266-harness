-- Load_list.lua
--[[
This is set of short utilities that are grouped together under utility function
for convenience.  
]]

local this, socket = unpack({...},1,2) 
local fld = this._fld
local list, total, listLen, fn, size, resp, blob = {}, 0, 0

-- TODO this listing might get longer than the max string length 
for fn, size in pairs(file.list()) do 
  list[#list+1] = fn .. "\t" .. size
  total = total + size
end

local listLen = #list

if listLen == 0 then
  resp = "list\t0\t0\tNo files found\r\n"  
else 
  blob = table.concat(list,"\r\n") .. "\r\n"
  list=nil
  resp = ("list\t0\t%u\t%u Files totalling %u bytes\r\n"):format(
          blob:len(), listLen, total)
end

this._fld=nil
socket:send(resp..blob)
