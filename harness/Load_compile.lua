-- Load_compile.lua
--[[
This function compiles the source file passed in the blob parameter 

Note that any code is loaded in CHUNK_SIZE bits to avoid the potential 
memory problems with manipulating large strings in the limited ESP8266 RAM.  
]]
local file = file
local this, socket = unpack({...},1,2) 
local CHUNK_SIZE = 1024
local fld, tmpName = this.fld, this._tmpName
local functionName = fld[2]
local sourceName, compiledName = functionName .. ".lua", functionName .. ".lc" 
local s, e = functionName:find('%.%w+')
local fn, error

if s then functionName = functionName:sub(s+1,e) end

if tmpName then -- compiling from file
  fn, error = load( tmpName, functionRoot )
  if not error then 
    node.compile( sourceName )
  end
  file.remove( sourceName )
else 
  fn, error = loadstring( this._blob, functionRoot )
  this._blob = nil
  if not error then 
    file.open(compiledName, "w")
    file.write(string.dump(fn))
    file.close()
  end
end

if error then
  msg = ("compile\t0\t0\t%s: %s\r\n"):format( sourceName, error)
else
  msg = "compile\t0\t1\r\n"
end

socket:send(msg)

