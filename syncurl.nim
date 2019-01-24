import system
import os
import hashes
import strutils
import httpclient

type 
  SynchronizedFileInfo = object
    url: string
    localPath: string
    localHash: Hash
  Config = ref object of RootObj
    checkIntervalMinutes: int
    infos: seq[SynchronizedFileInfo]

proc loadConfig(): Config =
  let configFile = open("syncurl.cfg", mode=FileMode.fmReadWriteExisting)
  defer: close configFile
  result = Config()  
  result.infos = newSeq[SynchronizedFileInfo]()
  result.checkIntervalMinutes = configFile.readLine().parseInt()
  var hashBytes: array[sizeof(Hash), uint8]
  while true:
    if configFile.readBytes(hashBytes, 0, sizeof(Hash)) < sizeof(Hash): break
    let hash = cast[ptr Hash](addr hashBytes)[]
    let sl = configFile.readLine().split(">", maxsplit=1)
    #if sl.len != 2: error 
    let sfi = SynchronizedFileInfo(url:sl[0].strip(), localPath:sl[1].strip(), localHash:hash)
    result.infos.add(sfi)

proc computeFileHash(filePath: string): Hash = 
  let file = open(filePath, mode=FileMode.fmRead)
  defer: close file
  return file.readAll().hash()

proc filesAreEqual(filePath1, filePath2: string): bool = 
  if os.getFileSize(filePath1) != os.getFileSize(filePath2): return false 
  return computeFileHash(filePath1) != computeFileHash(filePath2)

# The main loop
while true:
  let config = loadConfig()
  var change = false
  for sfi in config.infos:
    var client = newHttpClient()
    defer: close client    
    let downloadPath = sfi.localPath & ".new"
    if not os.existsFile(sfi.localPath):
      client.downloadFile(sfi.url, sfi.localPath)
      change = true
      continue
    client.downloadFile(sfi.url, downloadPath)
    if not filesAreEqual(downloadPath, sfi.localPath):
      try:
        echo "updating " & sfi.localPath
        os.removeFile(sfi.localPath)
        os.moveFile(downloadPath, sfi.localPath)
        change = true        
      except OSError:
        echo getCurrentExceptionMsg()
    else:
      os.removeFile(downloadPath)
  sleep 1000*60*config.checkIntervalMinutes # 600 s
