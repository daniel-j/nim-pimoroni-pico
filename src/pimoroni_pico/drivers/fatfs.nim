import std/os

const currentDir = currentSourcePath.parentDir

{.push header: currentDir / "../vendor/fatfs/ff.h".}

type
  HANDLE = void
  FF_SYNC_t = HANDLE

## FatFs Functional Configurations

const
  FFCONF_DEF* = 86631

  ##  Function Configurations
  FF_FS_READONLY* = 0
  FF_FS_MINIMIZE* = 0
  FF_USE_FIND* = 0
  FF_USE_MKFS* = 0
  FF_USE_FASTSEEK* = 0
  FF_USE_EXPAND* = 1
  FF_USE_CHMOD* = 0
  FF_USE_LABEL* = 0
  FF_USE_FORWARD* = 0
  FF_USE_STRFUNC* = 1
  FF_PRINT_LLI* = 0
  FF_PRINT_FLOAT* = 0
  FF_STRF_ENCODE* = 3

  ##  Locale and Namespace Configurations
  FF_CODE_PAGE* = 932
  FF_USE_LFN* = 1
  FF_MAX_LFN* = 255
  FF_LFN_UNICODE* = 0
  FF_LFN_BUF* = 255
  FF_SFN_BUF* = 12
  FF_FS_RPATH* = 1

  ##  Drive/Volume Configurations
  FF_VOLUMES* = 1
  FF_STR_VOLUME_ID* = 0
  FF_VOLUME_STRS* = ["RAM","NAND","CF","SD","SD2","USB","USB2","USB3"]
  FF_MULTI_PARTITION* = 0
  FF_MIN_SS* = 512
  FF_MAX_SS* = 512
  FF_LBA64* = 0
  FF_MIN_GPT* = 0x10000000
  FF_USE_TRIM* = 0

  ##  System Configurations
  FF_FS_TINY* = 0
  FF_FS_EXFAT* = 1
  FF_FS_NORTC* = 1
  FF_NORTC_MON* = 1
  FF_NORTC_MDAY* = 1
  FF_NORTC_YEAR* = 2020
  FF_FS_NOFSINFO* = 0
  FF_FS_LOCK* = 0
  FF_FS_REENTRANT* = 0
  FF_FS_TIMEOUT* = 1000


##################################################################################
##   FatFs - Generic FAT Filesystem module  R0.14b                              ## 
##################################################################################
## 
##  Copyright (C) 2021, ChaN, all right reserved.
## 
##  FatFs module is an open source software. Redistribution and use of FatFs in
##  source and binary forms, with or without modification, are permitted provided
##  that the following condition is met:
##
##  1. Redistributions of source code must retain the above copyright notice,
##     this condition and the following disclaimer.
## 
##  This software is provided by the copyright holder and contributors "AS IS"
##  and any warranties related to this software are DISCLAIMED.
##  The copyright owner or contributors be NOT LIABLE for any damages caused
##  by use of this software.
## 
##################################################################################

type
  UINT* {.importc.} = cuint    ##   int must be 16-bit or 32-bit
  BYTE* {.importc.} = uint8    ##   char must be 8-bit
  WORD* {.importc.} = uint16   ##   16-bit unsigned integer
  DWORD* {.importc.} = uint32  ##   32-bit unsigned integer
  QWORD* {.importc.} = uint64  ##  64-bit unsigned integer
  WCHAR* {.importc.} = WORD    ##   UTF-16 character type


when FF_FS_EXFAT.bool:
  type FSIZE_t* {.importc.} = QWORD
  when FF_LBA64.bool:
    type LBA_t* {.importc.} = QWORD
  else:
    type LBA_t* {.importc.} = DWORD
else:
  when FF_LBA64.bool:
    {.error: "exFAT needs to be enabled when enable 64-bit LBA".}
  type FSIZE_t* {.importc.} = DWORD
  type LBA_t* {.importc.} = DWORD

when FF_USE_LFN.bool and FF_LFN_UNICODE == 1:  ##  Unicode in UTF-16 encoding
  type TCHAR* {.importc.} = WCHAR
elif FF_USE_LFN.bool and FF_LFN_UNICODE == 2:  ##  Unicode in UTF-8 encoding
  type TCHAR* {.importc.} = char
elif FF_USE_LFN.bool and FF_LFN_UNICODE == 3:  ## Unicode in UTF-32 encoding
  type TCHAR* {.importc.} = DWORD
elif FF_USE_LFN.bool and (FF_LFN_UNICODE < 0 or FF_LFN_UNICODE > 3):
  {.error: "Wrong FF_LFN_UNICODE setting".}
else:  ##  ANSI/OEM code in SBCS/DBCS
  type TCHAR* {.importc.} = char


## Definitions of volume management

when FF_MULTI_PARTITION.bool:
  type
    PARTITION* {.bycopy, importc.} = object
      ##  Multiple partition configuration
      pd*: BYTE  ##  Physical drive number
      pt*: BYTE  ##  Partition: 0:Auto detect, 1-4:Forced partition)
  let
    VolToPart* {.importc.}: ptr UncheckedArray[PARTITION]
      ##   Volume - Partition mapping table

when FF_STR_VOLUME_ID.bool:
  let
    VolumeStr* {.importc.}: array[FF_VOLUMES, cstring]
      ##  User defied volume ID

type
  FATFS* {.bycopy, importc.} = object
    fs_type*: BYTE    ##   Filesystem type (0:not mounted)
    pdrv*: BYTE       ##   Associated physical drive
    n_fats*: BYTE     ##   Number of FATs (1 or 2)
    wflag*: BYTE      ##   win[] flag (b0:dirty)
    fsi_flag*: BYTE   ##   FSINFO flags (b7:disabled, b0:dirty)
    id*: WORD         ##   Volume mount ID
    n_rootdir*: WORD  ##   Number of root directory entries (FAT12/16)
    csize*: WORD      ##   Cluster size [sectors]
    when FF_MAX_SS != FF_MIN_SS:
      ssize*: WORD    ##  Sector size (512, 1024, 2048 or 4096)
    when FF_USE_LFN.bool:
      lfnbuf*: ptr WCHAR  ##  LFN working buffer
    when FF_FS_EXFAT.bool:
      dirbuf*: ptr BYTE  ##  Directory entry block scratchpad buffer for exFAT
    when FF_FS_REENTRANT.bool:
      sobj*: FF_SYNC_t  ##  Identifier of sync object
    when not FF_FS_READONLY.bool:
      last_clst*: DWORD  ##  Last allocated cluster
      free_clst*: DWORD  ##  Number of free clusters
    when FF_FS_RPATH.bool:
      cdir*: DWORD  ##  Current directory start cluster (0:root)
      when FF_FS_EXFAT.bool:
        cdc_scl*: DWORD   ##  Containing directory start cluster (invalid when cdir is 0)
        cdc_size*: DWORD  ##  b31-b8:Size of containing directory, b7-b0: Chain status
        cdc_ofs*: DWORD   ##  Offset in the containing directory (invalid when cdir is 0)
    n_fatent*: DWORD  ##   Number of FAT entries (number of clusters + 2)
    fsize*: DWORD     ##   Size of an FAT [sectors]
    volbase*: LBA_t   ##   Volume base sector
    fatbase*: LBA_t   ##   FAT base sector
    dirbase*: LBA_t   ##   Root directory base sector/cluster
    database*: LBA_t  ##   Data base sector
    when FF_FS_EXFAT.bool:
      bitbase*: LBA_t  ##  Allocation bitmap base sector
    winsect*: LBA_t   ##   Current sector appearing in the win[]
    win*: array[FF_MAX_SS, BYTE]  ##   Disk access window for Directory, FAT (and file data at tiny cfg)
  
  FFOBJID* {.bycopy, importc.} = object
    fs*: ptr FATFS     ##   Pointer to the hosting volume of this object
    id*: WORD          ##   Hosting volume mount ID
    attr*: BYTE        ##   Object attribute
    stat*: BYTE        ##   Object chain status (b1-0: =0:not contiguous, =2:contiguous, =3:fragmented in this session, b2:sub-directory stretched)
    sclust*: DWORD     ##   Object data start cluster (0:no cluster or root directory)
    objsize*: FSIZE_t  ##   Object size (valid when sclust != 0)
    when FF_FS_EXFAT.bool:
      n_cont*: DWORD   ##  Size of first fragment - 1 (valid when stat == 3)
      n_frag*: DWORD   ##  Size of last fragment needs to be written to FAT (valid when not zero)
      c_scl*: DWORD    ##  Containing directory start cluster (valid when sclust != 0)
      c_size*: DWORD   ##  b31-b8:Size of containing directory, b7-b0: Chain status (valid when c_scl != 0)
      c_ofs*: DWORD    ##  Offset in the containing directory (valid when file object and sclust != 0)
    when FF_FS_LOCK.bool:
      lockid*: UINT    ##  File lock ID origin from 1 (index of file semaphore table Files[])
  
  FIL* {.bycopy, importc.} = object
    obj*: FFOBJID   ##  Object identifier (must be the 1st member to detect invalid object pointer)
    flag*: BYTE     ##  File status flags
    err*: BYTE      ##  Abort flag (error code)
    fptr*: FSIZE_t  ##  File read/write pointer (Zeroed on file open)
    clust*: DWORD   ##  Current cluster of fpter (invalid when fptr is 0)
    sect*: LBA_t    ##  Sector number appearing in buf[] (0:invalid)
    when not FF_FS_READONLY.bool:
      dir_sect*: LBA_t    ##  Sector number containing the directory entry (not used at exFAT)
      dir_ptr*: ptr BYTE  ##  Pointer to the directory entry in the win[] (not used at exFAT)
    when FF_USE_FASTSEEK.bool:
      cltbl*: ptr DWORD   ##  Pointer to the cluster link map table (nulled on open, set by application)
    when not FF_FS_TINY.bool:
      buf*: array[FF_MAX_SS, BYTE]  ##  File private data read/write window

  DIR* {.bycopy, importc.} = object
    obj*: FFOBJID   ##  Object identifier
    dptr*: DWORD    ##  Current read/write offset
    clust*: DWORD   ##  Current cluster
    sect*: LBA_t    ##  Current sector (0:Read operation has terminated)
    dir*: ptr BYTE  ##  Pointer to the directory item in the win[]
    fn*: array[12, BYTE]  ##  SFN (in/out) {body[8],ext[3],status[1]}
    when FF_USE_LFN.bool:
      blk_ofs*: DWORD  ##  Offset of current entry block being processed (0xFFFFFFFF:Invalid)
    when FF_USE_FIND.bool:
      pat*: cstring  ##  Pointer to the name matching pattern
  
  FILINFO* {.bycopy, importc.} = object
    fsize*: FSIZE_t  ##  File size
    fdate*: WORD     ##  Modified date
    ftime*: WORD     ##  Modified time
    fattrib*: BYTE   ##  File attribute
    when FF_USE_LFN.bool:
      altname*: array[FF_SFN_BUF + 1, TCHAR]  ##  Altenative file name
      fname*: array[FF_LFN_BUF + 1, TCHAR]  ##  Primary file name
    else:
      fname*: array[12 + 1, TCHAR]  ##  File name

  MKFS_PARM* {.bycopy, importc.} = object
    fmt*: BYTE       ##  Format option (FM_FAT, FM_FAT32, FM_EXFAT and FM_SFD)
    n_fat*: BYTE     ##  Number of FATs
    align*: UINT     ##  Data area alignment (sector)
    n_root*: UINT    ##  Number of root directory entries
    au_size*: DWORD  ##  Cluster size (byte)

type
  FRESULT* {.pure #[, importc: "enum FRESULT"]#.} = enum
    FR_OK = 0               ## (0) Succeeded
    FR_DISK_ERR             ## (1) A hard error occurred in the low level disk I/O layer
    FR_INT_ERR              ## (2) Assertion failed
    FR_NOT_READY            ## (3) The physical drive cannot work
    FR_NO_FILE              ## (4) Could not find the file
    FR_NO_PATH              ## (5) Could not find the path
    FR_INVALID_NAME         ## (6) The path name format is invalid
    FR_DENIED               ## (7) Access denied due to prohibited access or directory full
    FR_EXIST                ## (8) Access denied due to prohibited access
    FR_INVALID_OBJECT       ## (9) The file/directory object is invalid
    FR_WRITE_PROTECTED      ## (10) The physical drive is write protected
    FR_INVALID_DRIVE        ## (11) The logical drive number is invalid
    FR_NOT_ENABLED          ## (12) The volume has no work area
    FR_NO_FILESYSTEM        ## (13) There is no valid FAT volume
    FR_MKFS_ABORTED         ## (14) The f_mkfs() aborted due to any problem
    FR_TIMEOUT              ## (15) Could not get a grant to access the volume within defined period
    FR_LOCKED               ## (16) The operation is rejected according to the file sharing policy
    FR_NOT_ENOUGH_CORE      ## (17) LFN working buffer could not be allocated
    FR_TOO_MANY_OPEN_FILES  ## (18) Number of open files > FF_FS_LOCK
    FR_INVALID_PARAMETER    ## (19) Given parameter is invalid


## FatFs module application interface

proc f_open*(fp: ptr FIL; path: cstring; mode: BYTE): FRESULT {.importc, cdecl.}
  ##   Open or create a file

proc f_close*(fp: ptr FIL): FRESULT {.importc, cdecl.}
  ##   Close an open file object

proc f_read*(fp: ptr FIL; buff: pointer; btr: UINT; br: ptr UINT): FRESULT {.importc, cdecl.}
  ##   Read data from the file

proc f_write*(fp: ptr FIL; buff: pointer; btw: UINT; bw: ptr UINT): FRESULT {.importc, cdecl.}
  ##   Write data to the file

proc f_lseek*(fp: ptr FIL; ofs: FSIZE_t): FRESULT {.importc, cdecl.}
  ##   Move file pointer of the file object

proc f_truncate*(fp: ptr FIL): FRESULT {.importc, cdecl.}
  ##   Truncate the file

proc f_sync*(fp: ptr FIL): FRESULT {.importc, cdecl.}
  ##   Flush cached data of the writing file

proc f_opendir*(dp: ptr DIR; path: cstring): FRESULT {.importc, cdecl.}
  ##   Open a directory

proc f_closedir*(dp: ptr DIR): FRESULT {.importc, cdecl.}
  ##   Close an open directory

proc f_readdir*(dp: ptr DIR; fno: ptr FILINFO): FRESULT {.importc, cdecl.}
  ##   Read a directory item

proc f_findfirst*(dp: ptr DIR; fno: ptr FILINFO; path: cstring; pattern: cstring): FRESULT {.importc, cdecl.}
  ##   Find first file

proc f_findnext*(dp: ptr DIR; fno: ptr FILINFO): FRESULT {.importc, cdecl.}
  ##   Find next file

proc f_mkdir*(path: cstring): FRESULT {.importc, cdecl.}
  ##   Create a sub directory

proc f_unlink*(path: cstring): FRESULT {.importc, cdecl.}
  ##   Delete an existing file or directory

proc f_rename*(path_old: cstring; path_new: cstring): FRESULT {.importc, cdecl.}
  ##   Rename/Move a file or directory

proc f_stat*(path: cstring; fno: ptr FILINFO): FRESULT {.importc, cdecl.}
  ##   Get file status

proc f_chmod*(path: cstring; attr: BYTE; mask: BYTE): FRESULT {.importc, cdecl.}
  ##   Change attribute of a file/dir

proc f_utime*(path: cstring; fno: ptr FILINFO): FRESULT {.importc, cdecl.}
  ##   Change timestamp of a file/dir

proc f_chdir*(path: cstring): FRESULT {.importc, cdecl.}
  ##   Change current directory

proc f_chdrive*(path: cstring): FRESULT {.importc, cdecl.}
  ##   Change current drive

proc f_getcwd*(buff: cstring; len: UINT): FRESULT {.importc, cdecl.}
  ##   Get current directory

proc f_getfree*(path: cstring; nclst: ptr DWORD; fatfs: ptr ptr FATFS): FRESULT {.importc, cdecl.}
  ##   Get number of free clusters on the drive

proc f_getlabel*(path: cstring; label: var cstring; vsn: ptr DWORD): FRESULT {.importc, cdecl.}
  ##   Get volume label

proc f_setlabel*(label: cstring): FRESULT {.importc, cdecl.}
  ##   Set volume label

proc f_forward*(fp: ptr FIL; `func`: proc (a1: ptr BYTE; a2: UINT): UINT {.cdecl.}; btf: UINT; bf: ptr UINT): FRESULT {.importc, cdecl.}
  ##   Forward data to the stream

proc f_expand*(fp: ptr FIL; fsz: FSIZE_t; opt: BYTE): FRESULT {.importc, cdecl.}
  ##   Allocate a contiguous block to the file

proc f_mount*(fs: ptr FATFS; path: cstring; opt: BYTE): FRESULT {.importc, cdecl.}
  ##   Mount/Unmount a logical drive

proc f_mkfs*(path: cstring; opt: ptr MKFS_PARM; work: pointer; len: UINT): FRESULT {.importc, cdecl.}
  ##   Create a FAT volume

proc f_fdisk*(pdrv: BYTE; ptbl: UncheckedArray[LBA_t]; work: pointer): FRESULT {.importc, cdecl.}
  ##   Divide a physical drive into some partitions

proc f_setcp*(cp: WORD): FRESULT {.importc, cdecl.}
  ##   Set current code page

proc f_putc*(c: TCHAR; fp: ptr FIL): cint {.importc, cdecl.}
  ##   Put a character to the file

proc f_puts*(str: cstring; cp: ptr FIL): cint {.importc, cdecl.}
  ##   Put a string to the file

proc f_printf*(fp: ptr FIL; str: cstring): cint {.importc, cdecl, varargs.}
  ##   Put a formatted string to the file

proc f_gets*(buff: cstring; len: cint; fp: ptr FIL): cstring {.importc, cdecl.}
  ##   Get a string from the file


func f_eof*(fp: ptr FIL): auto {.inline.} = fp.fptr == fp.obj.objsize
func f_error*(fp: ptr FIL): auto {.inline.} = fp.err
func f_tell*(fp: ptr FIL): auto {.inline.} = fp.fptr
func f_size*(fp: ptr FIL): auto {.inline.} = fp.obj.objsize
proc f_rewind*(fp: ptr FIL): auto {.inline.} = f_lseek(fp, 0)
proc f_rewinddir*(dp: ptr DIR): auto {.inline.} = f_readdir(dp, nil)
proc f_rmdir*(path: cstring): auto {.inline.} = f_unlink(path)
proc f_unmount*(path: cstring): auto {.inline.} = f_mount(nil, path, 0)


## Additional user defined functions

## RTC function
when not FF_FS_READONLY.bool and not FF_FS_NORTC.bool:
  proc get_fattime*(): DWORD {.importc, cdecl.}

## LFN support functions
when FF_USE_LFN >= 1:
  proc ff_oem2uni*(oem: WCHAR; cp: WORD): WCHAR {.importc, cdecl.}
    ##   OEM code to Unicode conversion

  proc ff_uni2oem*(uni: DWORD; cp: WORD): WCHAR {.importc, cdecl.}
    ##   Unicode to OEM code conversion

  proc ff_wtoupper*(uni: DWORD): DWORD {.importc, cdecl.}
    ##   Unicode upper-case conversion

when FF_USE_LFN == 3:
  proc ff_memalloc*(msize: UINT): pointer {.importc, cdecl.}
    ##   Allocate memory block

  proc ff_memfree*(mblock: pointer) {.importc, cdecl.}
    ##   Free memory block


## Sync functions
when FF_FS_REENTRANT.bool:
  proc ff_cre_syncobj*(vol: BYTE; sobj: ptr FF_SYNC_t): cint {.importc, cdecl.}
    ##   Create a sync object

  proc ff_req_grant*(sobj: FF_SYNC_t): cint {.importc, cdecl.}
    ##   Lock sync object

  proc ff_rel_grant*(sobj: FF_SYNC_t) {.importc, cdecl.}
    ##   Unlock sync object

  proc ff_del_syncobj*(sobj: FF_SYNC_t): cint {.importc, cdecl.}
    ##   Delete a sync object


## Flags and offset address

const
  ##  File access mode and open method flags (3rd argument of f_open)
  FA_READ* = 0x01
  FA_WRITE* = 0x02
  FA_OPEN_EXISTING* = 0x00
  FA_CREATE_NEW* = 0x04
  FA_CREATE_ALWAYS* = 0x08
  FA_OPEN_ALWAYS* = 0x10
  FA_OPEN_APPEND* = 0x30

  ##  Fast seek controls (2nd argument of f_lseek)
  CREATE_LINKMAP* = (cast[FSIZE_t](0) - typeof(cast[FSIZE_t](0))(1))

  ##  Format options (2nd argument of f_mkfs)
  FM_FAT*   = 0x01
  FM_FAT32* = 0x02
  FM_EXFAT* = 0x04
  FM_ANY*   = 0x07
  FM_SFD*   = 0x08

  ##  Filesystem type (FATFS.fs_type)
  FS_FAT12* = 1
  FS_FAT16* = 2
  FS_FAT32* = 3
  FS_EXFAT* = 4

  ##  File attribute bits for directory entry (FILINFO.fattrib)
  AM_RDO* = 0x01
  AM_HID* = 0x02
  AM_SYS* = 0x04
  AM_DIR* = 0x10
  AM_ARC* = 0x20

{.pop.}

func getFname*(self: FILINFO): string = $(cast[cstring](self.fname[0].unsafeAddr))
