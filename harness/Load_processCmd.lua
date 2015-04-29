-- Load_processCmd.lua  function Load.processCmd(socket,rec)
--[[
This version of the receiver is designed to capitalise on the assured delivery
of the TCP stack snd is always synchronous,in  that the requestor will always
wait for a response to a request before issuing another request.  However
due to the ability to receive blob data, an individal request may span
multiple receives.  However the first receive is always assumed to contain the
main request line.

The following class properties are used to store the context:
 - _lenLeft If set, then this indicated that a command has been received
            and the fields parsed but some of the blob is still outstanding
 - _blob    Any partial packet left over from last receive (if not nil)
 - _tmpName a negative size indicates that the blob should be written to a
            file rather than the blob.  Thiis holde the name of the file
 - _fld     Command parameters

Any errors in processing the command results in a reboot.

]]
return function(this, rec)
  local file = file
  local lenLeft = this._lenLeft or 0
  local fld,cmd,size,recLen

  package.loaded.Load_processCmd=nil -- make routine effemeral

  local function saveBlob(this, mode, rec)
    local tmpName = this._tmpName
    if tmpName then
      file.open(tmpName, mode)
      file.write(rec)
      file.flush()
      file.close()
    else
      this._blob = (this._blob or "") .. rec
    end
  end
print("Record: ", #rec, lenLeft )
  if lenLeft == 0 then --------- Process the next command line ------------

    -- Look for CR-LF and if not found set the this.rec fragment and return
    -- to wait for the next TCP receive
print(rec)
    local s,e = rec:find("\r?\n")
    if not s then node.restart() end

    -- We have complete request line so split it into separate tab-separated
    -- fields and extract the standard command and size fields
    local line = "\t" .. rec:sub(1, s-1)
    rec = rec:sub(e+1,-1)

    fld = {}
    line:gsub("\t[^\t]*", function(f) fld[#fld+1] = f:sub(2) end)
--for i = 1, #fld do print (i..": "..fld[i]) end
    size, recLen = tonumber(fld[2] or 0), #rec

    -- A negative size indicates that the blob is to be written to a temporary
    -- file.  Note that file-based blobs should in general be avoided for normal
    -- procesing as SPIFfs can only tolerate limited write cycles.
    if size < 0 then
      size = -size
      this._tmpName = ('tmp%u.tmp'):format(tmr.now())
      file.remove(this._tmpName)
    else
      this._tmpName = nil
    end
    fld[2] = size

    if size == 0 then             -- there is no blob so ignore any trailer
      lenLeft = 0
    else
      if recLen > size then
        rec = rec:sub(1,size)
        recLen = size
      end
      saveBlob(this, "w+", rec)
      lenLeft = size - recLen
    end

    this._fld, rec = fld, nil

  else -------  we are still consuming data so add this lot to the blob ------
    fld = this._fld
    size, recLen = tonumber(fld[2] or 0), rec:len()

    if recLen > lenLeft then
      rec = rec:sub(1,lenLeft)
      lenLeft = 0
    else
      lenLeft = lenLeft - recLen
    end

    saveBlob(this, "a+", rec)
  end

  ----- If lenLeft == 0 we can emit the command otherwise return a dummy ------
  --print ("executing " .. fld[1], lenLeft)
  if lenLeft == 0 then
    local cmd  = fld[1]
    this._lenLeft=nil
    if file.open("Load_"..cmd..".lc") or file.open("Load_"..cmd..".lua") then
      file.close()
      return cmd
    end
  else
    this._lenLeft = lenLeft
  end
end
