#
# FatFs License
#
# FatFs has being developped as a personal project of the author, ChaN. It is
# free from the code anyone else wrote at current release. Following code block
# shows a copy of the FatFs license document that heading the source files.
#
# /*----------------------------------------------------------------------------/
# /  FatFs - Generic FAT Filesystem Module  Rx.xx                               /
# /-----------------------------------------------------------------------------/
# /
# / Copyright (C) 20xx, ChaN, all right reserved.
# /
# / FatFs module is an open source software. Redistribution and use of FatFs in
# / source and binary forms, with or without modification, are permitted provided
# / that the following condition is met:
# /
# / 1. Redistributions of source code must retain the above copyright notice,
# /    this condition and the following disclaimer.
# /
# / This software is provided by the copyright holder and contributors "AS IS"
# / and any warranties related to this software are DISCLAIMED.
# / The copyright owner or contributors be NOT LIABLE for any damages caused
# / by use of this software.
# /----------------------------------------------------------------------------*/
#
# Therefore FatFs license is one of the BSD-style licenses, but there is a
# significant feature. FatFs is mainly intended for embedded systems. In order
# to extend the usability for commercial products, the redistributions of FatFs
# in binary form, such as embedded code, binary library and any forms without
# source code, do not need to include about FatFs in the documentations. This
# is equivalent to the 1-clause BSD license. Of course FatFs is compatible with
# the most of open source software licenses include GNU GPL. When you
# redistribute the FatFs source code with changes or create a fork, the license
# can also be changed to GNU GPL, BSD-style license or any open source software
# license that not conflict with FatFs license.
#

import std/os

const fatfsInclude = currentSourcePath.parentDir / ".." / "vendor" / "fatfs"

#[
{.compile: fatfsInclude / "ff.c".}
{.compile: fatfsInclude / "ffsystem.c".}
{.compile: fatfsInclude / "ffunicode.c".}
{.compile: fatfsInclude / "diskio.c".}
]#

when defined(nimcheck):
  include ../futharkgen/futhark_fatfs
else:
  import std/macros
  import picostdlib/helpers
  import futhark

  importc:
    outputPath currentSourcePath.parentDir / ".." / "futharkgen" / "futhark_fatfs.nim"

    compilerArg "--target=arm-none-eabi"
    compilerArg "-mthumb"
    compilerArg "-mcpu=cortex-m0plus"
    compilerArg "-fsigned-char"

    sysPath armSysrootInclude
    sysPath armInstallInclude
    path fatfsInclude

    renameCallback futharkRenameCallback

    "ff.h"


{.emit: "// picostdlib import: fatfs".}

# Nim helpers

import std/strutils
import picostdlib/hardware/rtc

func f_eof*(fp: ptr FIL): auto {.inline.} = fp.fptr == fp.obj.objsize
func f_error*(fp: ptr FIL): auto {.inline.} = fp.err
func f_tell*(fp: ptr FIL): auto {.inline.} = fp.fptr
func f_size*(fp: ptr FIL): auto {.inline.} = fp.obj.objsize
func f_rewind*(fp: ptr FIL): auto {.inline.} = f_lseek(fp, 0)
func f_rewinddir*(dp: ptr DIR): auto {.inline.} = f_readdir(dp, nil)
func f_rmdir*(path: cstring): auto {.inline.} = f_unlink(path)
func f_unmount*(path: cstring): auto {.inline.} = f_mount(nil, path, 0)

func getFname*(self: FILINFO): string = $(cast[cstring](self.fname[0].unsafeAddr))

func getFileDate*(self: FILINFO): tuple[year: int, month: int, day: int] =
  result.year = 1980 + (self.fdate.int shr 9)
  result.month = (self.fdate.int shr 5) and 0b1111
  result.day = self.fdate.int and 0b11111

func getFileTime*(self: FILINFO): tuple[hour: int, min: int, sec: int] =
  result.hour = self.ftime.int shr 11
  result.min = (self.ftime.int shr 5) and 0b111111
  result.sec = (self.ftime.int and 0b11111) * 2

func `$`*(fileTime: tuple[year: int, month: int, day: int]): string =
  return intToStr(fileTime.year, 4) & "-" & intToStr(fileTime.month, 2) & "-" & intToStr(fileTime.day, 2)

func `$`*(fileTime: tuple[hour: int, min: int, sec: int]): string =
  return intToStr(fileTime.hour, 2) & ":" & intToStr(fileTime.min, 2) & ":" & intToStr(fileTime.sec, 2)

proc get_fattime_impl(): DWORD {.exportc: "get_fattime", cdecl.} =
  var dt = DatetimeT(
    year: 2023,
    month: 1,
    day: 1
  )
  # If RTC is active, load current datetime.
  # Otherwise use fallback datetime defined above
  discard rtcGetDatetime(dt.addr)

  return (
    DWORD(dt.year - 1980) shl 25 or
    DWORD(dt.month + 1) shl 21 or
    DWORD(dt.day) shl 16 or
    DWORD(dt.hour) shl 11 or
    DWORD(dt.min) shl 5 or
    DWORD(dt.sec shr 1)
  )
