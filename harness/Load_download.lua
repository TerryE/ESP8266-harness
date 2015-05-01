-- Load_download.lua
--[[
This function compiles the source file passed in the blob parameter 

Note that any code is loaded in CHUNK_SIZE bits to avoid the potential 
memory problems with manipulating large strings in the limited ESP8266 RAM.  
]]

return function(this, socket)
  local file, node, table = file, node, table
  local name, size, mode, filename = unpack(this._fld)
  local tmpName, created = this._tmpName, false

  package.loaded.Load_download=nil -- make routine effemeral

  if tmpName then
    file.remove(filename)
    created = file.rename(this._tmpName, filename)
    
  elseif this._blob then
    file.remove(filename)
    if file.open(filename, "w+") and file.write(this._blob) then
       created=true
       file.close()
    end
  end
print(filename.. "created (".. file.list()[filename] .." bytes)")

  if created and mode == "compile" then
    node.compile(filename)
    file.remove(filename)
    local codeFile = filename:sub(1,-5)..".lc"
    local codeSize = file.list()[codeFile]
    if codeSize then
      filename, size = codeFile, codeSize
    else
      created = false
    end
  end
      
  socket:send(created and
           (("download\t0\t0\tFile %s (%u bytes) created\r\n"):format(
                filename, size)) or
           (("download\t0\t1\%s failed\r\n"):format(mode)))
end
