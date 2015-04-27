-- Load_list.lua
--[[
This is the directory list function  
]]
return function(this, socket)
  local fld = this._fld
  local list, total, listLen, fn, size, resp, blob = {}, 0, 0

  package.loaded.Load_list = nil -- make routine effemeral

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
    resp = ("list\t%u\t0\t%u Files totalling %u bytes\r\n"):format(
            #blob, listLen, total)
  end

  this._fld=nil
  socket:send(resp..blob)
end
