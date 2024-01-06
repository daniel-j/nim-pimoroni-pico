##
## JPEG Decoder
##
## written by Larry Bank
## bitbank@pobox.com
## Arduino port started 8/2/2020
## Original JPEG code written 26+ years ago :)
## The goal of this code is to decode baseline JPEG images
## using no more than 18K of RAM (if sent directly to an LCD display)
##
## Copyright 2020 BitBank Software, Inc. All Rights Reserved.
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##    http://www.apache.org/licenses/LICENSE-2.0
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
##

import std/os

const currentDir = currentSourcePath.parentDir
const jpegdecInclude = currentDir / ".." / "vendor" / "JPEGDEC"

{.compile: jpegdecInclude / "jpeg.inl.c".}

when defined(nimcheck):
  include ../futharkgen/futhark_jpegdec
else:
  import std/macros
  import picostdlib/helpers
  import futhark

  importc:
    outputPath currentSourcePath.parentDir / ".." / "futharkgen" / "futhark_jpegdec.nim"

    compilerArg "--target=arm-none-eabi"
    compilerArg "-mthumb"
    compilerArg "-mcpu=cortex-m0plus"
    compilerArg "-fsigned-char"
    compilerArg "-fshort-enums" # needed to get the right struct size

    sysPath armSysrootInclude
    sysPath armInstallInclude
    path jpegdecInclude

    define PICO_BUILD

    renameCallback futharkRenameCallback

    "JPEGDEC.h"

##
##  The JPEGDEC class wraps portable C code which does the actual work
##

type
  JPEGDEC* {.bycopy.} = object
    jpeg*: JPEGIMAGE

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
  self.jpeg.JPEGFile.fHandle = pfnOpen(szFilename.cstring, addr(self.jpeg.JPEGFile.iSize))
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
proc getLastError*(self: var JPEGDEC): int {.inline.} = self.jpeg.iError
proc setPixelType*(self: var JPEGDEC; iType: uint8) =
  if iType >= 0 and iType < INVALID_PIXEL_TYPE:
    self.jpeg.ucPixelType = iType
  else:
    self.jpeg.iError = JPEG_INVALID_PARAMETER.ord
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
