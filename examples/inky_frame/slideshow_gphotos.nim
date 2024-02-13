import std/random
import std/typetraits
import std/strutils
import std/streams
import std/json

import picostdlib
import picostdlib/pico/rand
import picostdlib/hardware/watchdog
import picostdlib/pico/cyw43_arch
import picostdlib/lib/httpclient

import pimoroni_pico/libraries/pico_graphics/drawjpeg
import pimoroni_pico/libraries/inky_frame
import pimoroni_pico/libraries/pico_graphics/error_diffusion

const pictureDelay = 5

const WIFI_SSID {.strdefine.} = ""
const WIFI_PASSWORD {.strdefine.} = ""
const googlePhotosShareUrl {.strdefine.} = "https://goo.gl/photos/hALfCAQzUXc8Gtci9"

# google photos parsing idea from
# https://github.com/moononournation/GooglePhotoClock/blob/master/GooglePhotoClock/GooglePhotoClock.ino
const seekPattern1 = "id=\"_ij\""
const seekPattern2 = "data:[null,[[\""
const seekPattern3 = "\"]}]"
const seekPattern4 = "[\""
const seekPattern5 = ",null,0], sideChannel"

discard stdioInitAll()

var inky: InkyFrame
inky.boot()

var fs: FATFS
var jpegDecoder: JpegDecoder[PicoGraphicsPen3Bit]

echo "Detected Inky Frame model: ", inky.kind

inky.init()

inky.led(Led.LedActivity, 100)

echo "Wake Up Events: ", inky.getWakeUpEvents()

jpegDecoder.init(inky)

jpegDecoder.errDiff.matrix = FloydSteinberg
jpegDecoder.errDiff.alternateRow = true
jpegDecoder.errDiff.variableDither = true
jpegDecoder.errDiff.hybridDither = false

jpegDecoder.colorModifier = proc (color: var Rgb) =
  color = color.level(gamma=1.4)

proc wifiInit(): bool =
  if cyw43ArchInit() != PicoErrorNone:
    echo "Wifi init failed!"
    return false

  echo "Wifi init successful!"

  var ssid = WIFI_SSID
  if ssid == "":
    stdout.write("Enter Wifi SSID: ")
    stdout.flushFile()
    ssid = stdinReadLine()

  var password = WIFI_PASSWORD
  if password == "":
    stdout.write("Enter Wifi password: ")
    stdout.flushFile()
    password = stdinReadLine()

  inky.led(Led.LedConnection, 100)

  cyw43ArchEnableStaMode()

  echo "Connecting to Wifi ", ssid

  let err = cyw43ArchWifiConnectTimeoutMs(ssid.cstring, password.cstring, AuthWpa2AesPsk, 30000)
  if err != PicoErrorNone:
    echo "Failed to connect! Error: ", $err
    inky.led(Led.LedConnection, 25)
    return false
  else:
    echo "Connected"

  inky.led(Led.LedConnection, 0)
  return true

proc seek(client: var HttpClient; sub: string; start: Natural = 0): bool =
  let size = 500
  while true:
    let line = client.read(max(client.beforeBuffer.len, size))
    if line.len == 0:
      client.beforeBuffer = ""
      echo "sub ", sub, " not found when seeking"
      return false

    let pos = line.find(sub)
    if pos != -1:
      client.beforeBuffer = line[pos..^1]
      return true

    if line.len > sub.len:
      client.beforeBuffer = line[^sub.len .. ^1]

proc readUntil(client: var HttpClient; sub: string; start: Natural = 0): string =
  let size = 500
  var skip = 0
  while true:
    let line = client.read(max(client.beforeBuffer.len, size))
    if line.len == 0:
      client.beforeBuffer = ""
      echo "sub ", sub, " not found when reading"
      return ""

    let pos = line.find(sub)
    if pos != -1:
      client.beforeBuffer = line[pos..^1]
      result.add(line[skip ..< pos])
      return result

    result.add(line[skip .. ^1])
    if line.len > sub.len:
      client.beforeBuffer = line[^sub.len .. ^1]
    skip = client.beforeBuffer.len

type
  PhotoInfo* = object
    url*: string
    id*: string
    width*: int
    height*: int
    imageUpdateDate*: BiggestInt
    albumAddDate*: BiggestInt
  
  AlbumInfo* = object
    name*: string
    id*: string
    createdDate*: BiggestInt
    updatedDate*: BiggestInt
    downloadUrl*: string
    thumbnailUrl*: string
    thumbnailWidth*: int
    thumbnailHeight*: int
    authorName*: string
    authorAvatarUrl*: string
    imageCount*: int
    shareUrl*: string

proc getGooglePhotos*(albumShareUrl: string; albumInfoOnly: bool) =
  var client: HttpClient
  if not client.begin(albumShareUrl):
    echo "error creating http client!"
    return

  echo "http client ok"

  client.setFollowRedirects(HTTPC_STRICT_FOLLOW_REDIRECTS)
  client.setRedirectLimit(3)
  # client.useHttp1_0(true)

  inky.led(Led.LedConnection, 100)

  var httpCode = client.get()

  defer:
    inky.led(Led.LedConnection, 0)

  if httpCode < 0:
    echo "http client error: ", HttpClientError(httpCode)
    return

  if httpCode != 200:
    echo "unexpected http code: ", httpCode
    return

  var foundStartingPoint = 0
  var photoCount = 0

  # client.setTimeout(60_000)

  if client.seek(seekPattern1) and client.seek(seekPattern2):
    discard client.read(seekPattern2.len - 2)

    while true:
      if not albumInfoOnly:
        echo "\nphoto info:"
        let photo = block:
          var photoInfo = client.readUntil(seekPattern3)
          if photoInfo.len != 0:
            photoInfo.add(client.read(seekPattern3.len))
            # echo photoInfo
            let photoInfoJson = parseJson(photoInfo)
            PhotoInfo(
              id: photoInfoJson[0].getStr(),
              url: photoInfoJson[1][0].getStr(),
              width: photoInfoJson[1][1].getInt(),
              height: photoInfoJson[1][2].getInt(),
              imageUpdateDate: photoInfoJson[2].getBiggestInt(),
              albumAddDate: photoInfoJson[5].getBiggestInt()
            )
          else:
            echo "error, unable to read image info"
            PhotoInfo()

        if photo.id.len == 0:
          return

        echo photo
        # echo photo.url & "=w640-h480"
        inc(photoCount)
      else:
        var photoInfo = client.seek(seekPattern3)
        if not photoInfo:
          echo "error, unable to read image info"
          return
        discard client.read(seekPattern3.len)

      if client.read(1) != ",":
        if not client.seek(seekPattern4):
          echo "error, unable to find album info"
          return
        break

    if not albumInfoOnly:
      echo "\nfound ", photoCount, " photos in album"

    echo "\nalbum info:"
    let album = block:
      let albumInfo = client.readUntil(seekPattern5)
      # echo albumInfo
      let albumInfoJson = parseJson(albumInfo)
      AlbumInfo(
        id: albumInfoJson[0].getStr(),
        name: albumInfoJson[1].getStr(),
        createdDate: albumInfoJson[2][0].getBiggestInt(), # maybe?
        updatedDate: albumInfoJson[2][1].getBiggestInt(), # maybe?
        downloadUrl: albumInfoJson[3].getStr(),
        thumbnailUrl: albumInfoJson[4][0].getStr(),
        thumbnailWidth: albumInfoJson[4][1].getInt(),
        thumbnailHeight: albumInfoJson[4][2].getInt(),
        authorName: albumInfoJson[5][11][0].getStr(),
        authorAvatarUrl: albumInfoJson[5][12][0].getStr(),
        imageCount: albumInfoJson[21].getInt(),
        shareUrl: albumInfoJson[32].getStr()
      )
    echo album
    
  else:
    echo "seek pattern not found"

  client.finish()


proc drawFile(filename: string) =
  inky.led(LedActivity, 50)
  let startTime = getAbsoluteTime()
  inky.setPen(White)
  inky.setBorder(White)
  inky.clear()

  let (x, y, w, h) = case inky.kind:
    of InkyFrame4_0: (0, 0, inky.width, inky.height)
    of InkyFrame5_7: (0, -1, 600, 450)
    of InkyFrame7_3: (-27, 0, 854, 480)

  # let (x, y, w, h) = (0, 0, inky.width, inky.height)

  if jpegDecoder.drawJpeg(filename, x, y, w, h, gravity=(0.5f, 0.5f), contains = true, DrawMode.ErrorDiffusion) == 1:
    let endTime = getAbsoluteTime()
    echo "Time: ", diffUs(startTime, endTime) div 1000, "ms"
    inky.led(LedActivity, 100)
    echo "Updating... (" & filename & ")"
    inky.update()
    echo "Update complete. Sleeping..."
    inky.led(LedActivity, 0)
    # inky.sleep(pictureDelay, true)
    sleepMs(pictureDelay * 60 * 1000)
  else:
    inky.led(LedActivity, 0)

iterator walkDir(directory: string): FILINFO =
  var file: FILINFO
  var dir: DIR
  discard f_opendir(dir.addr, directory.cstring)
  while f_readdir(dir.addr, file.addr) == FR_OK and file.fname[0].bool:
    yield file

proc getFileN(directory: string; n: Natural): FILINFO =
  var i = 0
  for file in walkDir(directory):
    if i == n:
      return file
    inc(i)

proc inkyProc() =
  inky.led(Led.LedActivity, 0)
  echo "Starting..."

  echo "Mounting SD card..."

  let fr = f_mount(fs.addr, "".cstring, 1)
  if fr != FR_OK:
    echo "Failed to mount SD card, error: ", fr

  if fr == FR_OK:
    echo "Listing SD card contents.."
    let directory = "/images"
    var fileCount = 0
    for i in walkDir(directory):
      inc(fileCount)
    echo "number of files: ", fileCount
    var fileOrder = newSeq[int](fileCount)
    for i in 0..<fileCount:
      fileOrder[i] = i
    let seed = cast[int64](getRand64())
    echo "rand seed: ", seed
    randomize(seed)
    fileOrder.shuffle()
    echo "shuffled file order:"
    for i in fileOrder:
      let file = getFileN(directory, i)
      echo "- ", file.getFname()

    echo "starting main image loop"

    for i in fileOrder:
      let file = getFileN(directory, i)
      echo "- ", file.getFname(), " ", file.fsize
      if file.fsize == 0:
        continue

      echo "- file timestamp: ", $file.getFileDate(), " ", $file.getFileTime()

      let filename = directory & "/" & file.getFname()

      drawFile(filename)

    discard f_unmount("")
    sleepMs(30 * 1000)
    watchdogReboot(0, 0, 0)


if wifiInit():
  getGooglePhotos(googlePhotosShareUrl, albumInfoOnly = false)
  # inkyProc()

while true:
  inky.led(LedActivity, 100)
  CYW43_WL_GPIO_LED_PIN.put(High)
  sleepMs(250)
  inky.led(LedActivity, 0)
  CYW43_WL_GPIO_LED_PIN.put(Low)
  sleepMs(250)
  tightLoopContents()
