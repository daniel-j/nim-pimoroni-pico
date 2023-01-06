##
##  Copyright 2020 BitBank Software, Inc. All Rights Reserved.
##  Licensed under the Apache License, Version 2.0 (the "License");
##  you may not use this file except in compliance with the License.
##  You may obtain a copy of the License at
##     http://www.apache.org/licenses/LICENSE-2.0
##  Unless required by applicable law or agreed to in writing, software
##  distributed under the License is distributed on an "AS IS" BASIS,
##  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
##  See the License for the specific language governing permissions and
##  limitations under the License.
## ===========================================================================
##

##
##  JPEG Decoder
##  Written by Larry Bank
##  Copyright (c) 2020 BitBank Software, Inc.
##
##  Designed to decode baseline JPEG images (8 or 24-bpp)
##  using less than 22K of RAM
##

from std/os import parentDir, `/`
import std/strutils

const currentDir = currentSourcePath.parentDir

{.push header: currentDir / "../vendor/JPEGDEC/JPEGDEC.h" }
{.emit: staticRead(currentDir / "../vendor/JPEGDEC/jpeg.inl").replace("JPEGDEC.h", currentDir / "../vendor/JPEGDEC/JPEGDEC.h").}


##  Defines and variables

const
  FILE_HIGHWATER* = 1536
  JPEG_FILE_BUF_SIZE* = 2048
  HUFF_TABLEN* = 273
  HUFF11SIZE* = (1 shl 11)
  DC_TABLE_SIZE* = 1024
  DCTSIZE* = 64
  MAX_MCU_COUNT* = 6
  MAX_COMPS_IN_SCAN* = 4
  MAX_BUFFERED_PIXELS* = 1024

##  Decoder options

const
  JPEG_AUTO_ROTATE* = 1
  JPEG_SCALE_HALF* = 2
  JPEG_SCALE_QUARTER* = 4
  JPEG_SCALE_EIGHTH* = 8
  JPEG_LE_PIXELS* = 16
  JPEG_EXIF_THUMBNAIL* = 32
  JPEG_LUMA_ONLY* = 64
  MCU0* = (DCTSIZE * 0)
  MCU1* = (DCTSIZE * 1)
  MCU2* = (DCTSIZE * 2)
  MCU3* = (DCTSIZE * 3)
  MCU4* = (DCTSIZE * 4)
  MCU5* = (DCTSIZE * 5)

##  Pixel types (defaults to little endian RGB565)

const
  RGB565_LITTLE_ENDIAN* = 0
  RGB565_BIG_ENDIAN* = 1
  EIGHT_BIT_GRAYSCALE* = 2
  FOUR_BIT_DITHERED* = 3
  TWO_BIT_DITHERED* = 4
  ONE_BIT_DITHERED* = 5
  INVALID_PIXEL_TYPE* = 6

const
  JPEG_MEM_RAM* = 0
  JPEG_MEM_FLASH* = 1

##  Error codes returned by getLastError()

const
  JPEG_SUCCESS* = 0
  JPEG_INVALID_PARAMETER* = 1
  JPEG_DECODE_ERROR* = 2
  JPEG_UNSUPPORTED_FEATURE* = 3
  JPEG_INVALID_FILE* = 4

type
  BUFFERED_BITS* {.importc: "BUFFERED_BITS", bycopy.} = object
    pBuf* {.importc: "pBuf".}: ptr uint8 ##  buffer pointer
    ulBits* {.importc: "ulBits".}: uint32 ##  buffered bits
    ulBitOff* {.importc: "ulBitOff".}: uint32 ##  current bit offset

  JPEGFILE* {.importc: "JPEGFILE", bycopy.} = object
    iPos* {.importc: "iPos".}: int32 ##  current file position
    iSize* {.importc: "iSize".}: int32 ##  file size
    pData* {.importc: "pData".}: ptr uint8 ##  memory file pointer
    fHandle* {.importc: "fHandle".}: pointer ##  class pointer to File/SdFat or whatever you want

  JPEGDRAW* {.importc: "JPEGDRAW", bycopy.} = object
    x* {.importc: "x".}: cint
    y* {.importc: "y".}: cint    ##  upper left corner of current MCU
    iWidth* {.importc: "iWidth".}: cint
    iHeight* {.importc: "iHeight".}: cint ##  size of this MCU
    iBpp* {.importc: "iBpp".}: cint ##  bit depth of the pixels (8 or 16)
    pPixels* {.importc: "pPixels".}: ptr uint16 ##  16-bit pixels
    pUser* {.importc: "pUser".}: pointer


##  Callback function prototypes

type
  JPEG_READ_CALLBACK* = proc (pFile: ptr JPEGFILE; pBuf: ptr uint8; iLen: int32): int32 {.cdecl.}
  JPEG_SEEK_CALLBACK* = proc (pFile: ptr JPEGFILE; iPosition: int32): int32 {.cdecl.}
  JPEG_DRAW_CALLBACK* = proc (pDraw: ptr JPEGDRAW): cint {.cdecl.}
  JPEG_OPEN_CALLBACK* = proc (szFilename: cstring; pFileSize: ptr int32): pointer {.cdecl.}
  JPEG_CLOSE_CALLBACK* = proc (pHandle: pointer): void {.cdecl.}

##  JPEG color component info

type
  JPEGCOMPINFO* {.importc: "JPEGCOMPINFO", bycopy.} = object ##  These values are fixed over the whole image
                                                                            ##  For compression, they must be supplied by the user interface
                                                                            ##  for decompression, they are read from the SOF marker.
    component_needed* {.importc: "component_needed".}: uint8 ##   do we need the value of this component?
    component_id* {.importc: "component_id".}: uint8 ##  identifier for this component (0..255)
    component_index* {.importc: "component_index".}: uint8 ##  its index in SOF or cinfo->comp_info[]
                                                        ## unsigned char h_samp_factor;    /* horizontal sampling factor (1..4) */
                                                        ## unsigned char v_samp_factor;    /* vertical sampling factor (1..4) */
    quant_tbl_no* {.importc: "quant_tbl_no".}: uint8 ##  quantization table selector (0..3)
                                                  ##  These values may vary between scans
                                                  ##  For compression, they must be supplied by the user interface
                                                  ##  for decompression, they are read from the SOS marker.
    dc_tbl_no* {.importc: "dc_tbl_no".}: uint8 ##  DC entropy table selector (0..3)
    ac_tbl_no* {.importc: "ac_tbl_no".}: uint8 ##  AC entropy table selector (0..3)
                                            ##  These values are computed during compression or decompression startup
                                            ## int true_comp_width;  /* component's image width in samples */
                                            ## int true_comp_height; /* component's image height in samples */
                                            ##  the above are the logical dimensions of the downsampled image
                                            ##  These values are computed before starting a scan of the component
                                            ## int MCU_width;        /* number of blocks per MCU, horizontally */
                                            ## int MCU_height;       /* number of blocks per MCU, vertically */
                                            ## int MCU_blocks;       /* MCU_width * MCU_height */
                                            ## int downsampled_width; /* image width in samples, after expansion */
                                            ## int downsampled_height; /* image height in samples, after expansion */
                                            ##  the above are the true_comp_xxx values rounded up to multiples of
                                            ##  the MCU dimensions; these are the working dimensions of the array
                                            ##  as it is passed through the DCT or IDCT step.  NOTE: these values
                                            ##  differ depending on whether the component is interleaved or not!!
                                            ##  This flag is used only for decompression.  In cases where some of the
                                            ##  components will be ignored (eg grayscale output from YCbCr image),
                                            ##  we can skip IDCT etc. computations for the unused components.


##
##  our private structure to hold a JPEG image decode state
##

type
  JPEGIMAGE* {.importc: "JPEGIMAGE", bycopy.} = object
    iWidth* {.importc: "iWidth".}: cint
    iHeight* {.importc: "iHeight".}: cint ##  image size
    iThumbWidth* {.importc: "iThumbWidth".}: cint
    iThumbHeight* {.importc: "iThumbHeight".}: cint ##  thumbnail size (if present)
    iThumbData* {.importc: "iThumbData".}: cint ##  offset to image data
    iXOffset* {.importc: "iXOffset".}: cint
    iYOffset* {.importc: "iYOffset".}: cint ##  placement on the display
    ucBpp* {.importc: "ucBpp".}: uint8
    ucSubSample* {.importc: "ucSubSample".}: uint8
    ucHuffTableUsed* {.importc: "ucHuffTableUsed".}: uint8
    ucMode* {.importc: "ucMode".}: uint8
    ucOrientation* {.importc: "ucOrientation".}: uint8
    ucHasThumb* {.importc: "ucHasThumb".}: uint8
    b11Bit* {.importc: "b11Bit".}: uint8
    ucComponentsInScan* {.importc: "ucComponentsInScan".}: uint8
    cApproxBitsLow* {.importc: "cApproxBitsLow".}: uint8
    cApproxBitsHigh* {.importc: "cApproxBitsHigh".}: uint8
    iScanStart* {.importc: "iScanStart".}: uint8
    iScanEnd* {.importc: "iScanEnd".}: uint8
    ucFF* {.importc: "ucFF".}: uint8
    ucNumComponents* {.importc: "ucNumComponents".}: uint8
    ucACTable* {.importc: "ucACTable".}: uint8
    ucDCTable* {.importc: "ucDCTable".}: uint8
    ucMaxACCol* {.importc: "ucMaxACCol".}: uint8
    ucMaxACRow* {.importc: "ucMaxACRow".}: uint8
    ucMemType* {.importc: "ucMemType".}: uint8
    ucPixelType* {.importc: "ucPixelType".}: uint8
    iEXIF* {.importc: "iEXIF".}: cint ##  Offset to EXIF 'TIFF' file
    iError* {.importc: "iError".}: cint
    iOptions* {.importc: "iOptions".}: cint
    iVLCOff* {.importc: "iVLCOff".}: cint ##  current VLC data offset
    iVLCSize* {.importc: "iVLCSize".}: cint ##  current quantity of data in the VLC buffer
    iResInterval* {.importc: "iResInterval".}: cint
    iResCount* {.importc: "iResCount".}: cint ##  restart interval
    iMaxMCUs* {.importc: "iMaxMCUs".}: cint ##  max MCUs of pixels per JPEGDraw call
    pfnRead* {.importc: "pfnRead".}: JPEG_READ_CALLBACK
    pfnSeek* {.importc: "pfnSeek".}: JPEG_SEEK_CALLBACK
    pfnDraw* {.importc: "pfnDraw".}: JPEG_DRAW_CALLBACK
    pfnOpen* {.importc: "pfnOpen".}: JPEG_OPEN_CALLBACK
    pfnClose* {.importc: "pfnClose".}: JPEG_CLOSE_CALLBACK
    JPCI* {.importc: "JPCI".}: array[MAX_COMPS_IN_SCAN, JPEGCOMPINFO] ##  Max color components
    JPEGFile* {.importc: "JPEGFile".}: JPEGFILE
    bb* {.importc: "bb".}: BUFFERED_BITS
    pUser* {.importc: "pUser".}: pointer
    pDitherBuffer* {.importc: "pDitherBuffer".}: ptr uint8 ##  provided externally to do Floyd-Steinberg dithering
    usPixels* {.importc: "usPixels".}: array[MAX_BUFFERED_PIXELS, uint16]
    sMCUs* {.importc: "sMCUs".}: array[DCTSIZE * MAX_MCU_COUNT, int16] ##  4:2:0 needs 6 DCT blocks per MCU
    sQuantTable* {.importc: "sQuantTable".}: array[DCTSIZE * 4, int16] ##  quantization tables
    ucFileBuf* {.importc: "ucFileBuf".}: array[JPEG_FILE_BUF_SIZE, uint8] ##  holds temp data and pixel stack
    ucHuffDC* {.importc: "ucHuffDC".}: array[DC_TABLE_SIZE * 2, uint8] ##  up to 2 'short' tables
    usHuffAC* {.importc: "usHuffAC".}: array[HUFF11SIZE * 2, uint16]


##  Due to unaligned memory causing an exception, we have to do these macros the slow way
template INTELSHORT*(p: untyped): untyped =
  ((p[]) + ((p + 1)[] shl 8))

template INTELLONG*(p: untyped): untyped =
  ((p[]) + ((p + 1)[] shl 8) + ((p + 2)[] shl 16) + ((p + 3)[] shl 24))

template MOTOSHORT*(p: untyped): untyped =
  ((((p)[]) shl 8) + ((p + 1)[]))

template MOTOLONG*(p: untyped): untyped =
  (((p[]) shl 24) + (((p + 1)[]) shl 16) + (((p + 2)[]) shl 8) + ((p + 3)[]))

##  Must be a 32-bit target processor
const
  REGISTER_WIDTH* = 32

{.pop.}

##  forward references
proc JPEGInit(pJPEG: ptr JPEGIMAGE): cint {.importc: "JPEGInit".}
proc JPEGParseInfo(pPage: ptr JPEGIMAGE; bExtractThumb: cint): cint {.importc: "JPEGParseInfo".}
proc JPEGGetMoreData(pPage: ptr JPEGIMAGE) {.importc: "JPEGGetMoreData".}
proc DecodeJPEG(pImage: ptr JPEGIMAGE): cint {.importc: "DecodeJPEG".}


##
##  The JPEGDEC class wraps portable C code which does the actual work
##

type
  JPEGDEC* {.bycopy.} = object
    jpeg: JPEGIMAGE

##
##  Memory initialization
##

proc openRAM*(self: var JPEGDEC; pData: ptr uint8; iDataSize: cint; pfnDraw: JPEG_DRAW_CALLBACK): cint =
  zeroMem(self.jpeg.addr, JPEGIMAGE.sizeof)
  self.jpeg.ucMemType = JPEG_MEM_RAM
  #self.jpeg.pfnRead = readRAM
  #self.jpeg.pfnSeek = seekMem
  self.jpeg.pfnDraw = pfnDraw
  self.jpeg.pfnOpen = nil
  self.jpeg.pfnClose = nil
  self.jpeg.JPEGFile.iSize = iDataSize
  self.jpeg.JPEGFile.pData = pData
  self.jpeg.iMaxMCUs = 1000  ##  set to an unnaturally high value to start
  return JPEGInit(self.jpeg.addr)

proc openFLASH*(self: var JPEGDEC; pData: ptr uint8; iDataSize: cint; pfnDraw: JPEG_DRAW_CALLBACK): cint =
  zeroMem(self.jpeg.addr, JPEGIMAGE.sizeof)
  self.jpeg.ucMemType = JPEG_MEM_FLASH
  #self.jpeg.pfnRead = readFLASH
  #self.jpeg.pfnSeek = seekMem
  self.jpeg.pfnDraw = pfnDraw
  self.jpeg.pfnOpen = nil
  self.jpeg.pfnClose = nil
  self.jpeg.JPEGFile.iSize = iDataSize
  self.jpeg.JPEGFile.pData = pData
  self.jpeg.iMaxMCUs = 1000  ##  set to an unnaturally high value to start
  return JPEGInit(self.jpeg.addr)

##
##  File (SD/MMC) based initialization
##

proc open*(self: var JPEGDEC; szFilename: string; pfnOpen: JPEG_OPEN_CALLBACK; pfnClose: JPEG_CLOSE_CALLBACK; pfnRead: JPEG_READ_CALLBACK; pfnSeek: JPEG_SEEK_CALLBACK; pfnDraw: JPEG_DRAW_CALLBACK): cint =
  zeroMem(self.jpeg.addr, JPEGIMAGE.sizeof)
  self.jpeg.pfnRead = pfnRead
  self.jpeg.pfnSeek = pfnSeek
  self.jpeg.pfnDraw = pfnDraw
  self.jpeg.pfnOpen = pfnOpen
  self.jpeg.pfnClose = pfnClose
  self.jpeg.iMaxMCUs = 1000  ##  set to an unnaturally high value to start
  self.jpeg.JPEGFile.fHandle = pfnOpen(szFilename, addr(self.jpeg.JPEGFile.iSize))
  if self.jpeg.JPEGFile.fHandle == nil:
    return 0
  return JPEGInit(self.jpeg.addr)

##
##  data stream initialization
##

proc open*(self: var JPEGDEC; fHandle: pointer; iDataSize: cint; pfnClose: JPEG_CLOSE_CALLBACK; pfnRead: JPEG_READ_CALLBACK; pfnSeek: JPEG_SEEK_CALLBACK; pfnDraw: JPEG_DRAW_CALLBACK): cint =
  zeroMem(self.jpeg.addr, JPEGIMAGE.sizeof)
  self.jpeg.pfnRead = pfnRead
  self.jpeg.pfnSeek = pfnSeek
  self.jpeg.pfnDraw = pfnDraw
  self.jpeg.pfnClose = pfnClose
  self.jpeg.iMaxMCUs = 1000   ##  set to an unnaturally high value to start
  self.jpeg.JPEGFile.iSize = iDataSize
  self.jpeg.JPEGFile.fHandle = fHandle
  return JPEGInit(self.jpeg.addr)

proc close*(self: var JPEGDEC)  =
  #if self.jpeg.pfnClose != nil:
  self.jpeg.pfnClose(self.jpeg.JPEGFile.fHandle)

##
##  Decode the image
##  returns:
##  1 = good result
##  0 = error
##

proc decode*(self: var JPEGDEC; x: cint; y: cint; iOptions: cint): cint =
  self.jpeg.iXOffset = x
  self.jpeg.iYOffset = y
  self.jpeg.iOptions = iOptions
  return DecodeJPEG(self.jpeg.addr)

proc decodeDither*(self: var JPEGDEC; pDither: ptr uint8; iOptions: cint): cint =
  self.jpeg.iOptions = iOptions
  self.jpeg.pDitherBuffer = pDither
  return DecodeJPEG(self.jpeg.addr)

proc getOrientation*(self: var JPEGDEC): cint {.inline.} = self.jpeg.ucOrientation.cint
proc getWidth*(self: var JPEGDEC): cint {.inline.} = self.jpeg.iWidth
proc getHeight*(self: var JPEGDEC): cint {.inline.} = self.jpeg.iHeight
proc getBpp*(self: var JPEGDEC): cint {.inline.} = self.jpeg.ucBpp.cint

##
##  set draw callback user pointer variable
##

proc setUserPointer*(self: var JPEGDEC; p: pointer) =
  self.jpeg.pUser = p

proc getSubSample*(self: var JPEGDEC): cint {.inline.} = self.jpeg.ucSubSample.cint
proc hasThumb*(self: var JPEGDEC): cint = self.jpeg.ucHasThumb.cint
proc getThumbWidth*(self: var JPEGDEC): cint {.inline.} = self.jpeg.iThumbWidth
proc getThumbHeight*(self: var JPEGDEC): cint {.inline.} = self.jpeg.iThumbHeight
proc getLastError*(self: var JPEGDEC): cint {.inline.} = self.jpeg.iError
proc setPixelType*(self: var JPEGDEC; iType: cint) =
  if iType >= 0 and iType < INVALID_PIXEL_TYPE:
    self.jpeg.ucPixelType = cast[uint8](iType)
  else:
    self.jpeg.iError = JPEG_INVALID_PARAMETER
proc setMaxOutputSize*(self: var JPEGDEC; iMaxMCUs: cint) =
  if iMaxMCUs < 1:
    self.jpeg.iMaxMCUs = 1
  else:
    self.jpeg.iMaxMCUs = iMaxMCUs

#[
when defined(FS_H):
  proc FileRead*(handle: ptr JPEGFILE; buffer: ptr uint8; length: int32_t): int32_t =
    return (cast[ptr File]((handle.fHandle))).read(buffer, length)

  proc FileSeek*(handle: ptr JPEGFILE; position: int32_t): int32_t =
    return (cast[ptr File]((handle.fHandle))).seek(position)

  proc FileClose*(handle: pointer) =
    (cast[ptr File](handle)).close()

  proc open*(self: var JPEGDEC; file: var File; pfnDraw: JPEG_DRAW_CALLBACK): cint =
    if not file:
      return 0
    zeroMem(self.jpeg.addr, JPEGIMAGE.sizeof)
    self.jpeg.pfnRead = FileRead
    self.jpeg.pfnSeek = FileSeek
    self.jpeg.pfnClose = FileClose
    self.jpeg.pfnDraw = pfnDraw
    self.jpeg.iMaxMCUs = 1000
    self.jpeg.JPEGFile.fHandle = addr(file)
    self.jpeg.JPEGFile.iSize = file.size()
    return JPEGInit(addr(self.jpeg))
]#
