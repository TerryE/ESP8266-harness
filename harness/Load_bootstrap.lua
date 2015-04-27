-- Load_bootstap.lua
--[[
This function clears the ESP 8266 down to a known state by reformatting the 
SPIflashFS and then the files needed to rebuild the  

Note that any code is loaded in CHUNK_SIZE bits to avoid the potential 
memory problems with manipulating large strings in the limited ESP8266 RAM.  
]]
local file = file
local this, socket = unpack({...},1,2) 
local fileList = file.list()
local CHUNK_SIZE = 1024
local msg

--[["init.lua"]]
local keep = { ["rpc-client.lua"] = {}, 
  ["Load_processCmd.lc"] = {}, 
  ["Load_bootstap.lc"] = {}, 
  ["Load_compile.lc"] = {}, } 

for file, code in pairs(keep) do
  local size = fileList[file]
  local code = keep[file]
  if not size then 
    print( "Cannot load "..file )
    keep = nil
    break
  end
  file.open(file)
  repeat
    local codeSize = size
    if codeSize > CHUNK_SIZE then codeSize = CHUNK_SIZE end
    size = size - codeSize
    code[#code+1] = file.read(codeSize)
  until size == 0
  file.close()
end

if keep then
  file.format()

  for file, code in pairs(keep) do
    local code, i = keep[file]
    print( ("Rewriting %s (%u bytes)"):format(file, fileList[file]))
    file.open(file, "w")
    for i = 1, #code, 1 do
      file.write(code[i])
    end
    file.close()
  end
  msg = "bootstrap\t0\t1\tFile system reformatted, " .. #keep .. 
        "files written\r\n"

else
  msg = "bootstrap\t0\t0\tFiles missing manual formart needed\r\n"  
end

socket:send(msg)

