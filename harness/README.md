
The first line of the both the request and the
response is an ASCII tab-separated line (TSL) ending in CR-LF and follow by an
optional binary blob. No escaping is supported in the TSL, so the line is 
considered to be a list of tab-separated parameters, so clearly you can't have 
a tab in a parameter.    
  
The first two fields in any request are the request name the size of the binary
field (blob), which is usually zero. The remaining parameters (including any
blob are request-specific. The blob can be anything but must be the specified
size. The size is signed:
 -  A positive length means that the blob is retained in RAM
 -  A negative means that it is written to a temporary file and the filename 
    passed instead to the requested routine. This is used for the rare 
    occasions that a large blob parameter might not fit into memory, e.g. when 
    downloading a source file to compile. Also note that because the SPIFlash
    file system has a limited write life, use of file-based blobs should be
    avoided where possible.
 
The compiled version of this file is normally written to init.lua.

Note that this bootstrap code is alway in RAM so is a fixed overhead. The idea 
is to move as much code as possible into the dynamically loaded method 
overlays so that this overhead is as lean as is possible.


