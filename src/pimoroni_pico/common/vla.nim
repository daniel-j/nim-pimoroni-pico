include system/ansi_c

proc alloca(n: cint): pointer {.importc, header: "<alloca.h>".}

type
  VarLenArray*[T] = object
    len: int
    data: ptr UncheckedArray[T]

template `[]`*[T](a: VarLenArray[T], i: Natural): T =
  when compileOption"checks":
    assert i >= 0 and i < a.len
  a.data[i]

template `[]=`*[T](a: VarLenArray[T], i: Natural, x: T) =
  when compileOption"checks":
    assert i >= 0 and i < a.len
  a.data[i] = x

template len*[T](a: VarLenArray[T]): int =
  a.len

template newVLA*(T: typedesc, n: Natural): untyped =
  let bytes = sizeof(T)*n
  var vla : VarLenArray[T]
  vla.data= cast[ptr UncheckedArray[T]](alloca(bytes.cint))
  c_memset(vla.data, 0, (csize_t)(bytes))
  zeroMem(vla.data, bytes)
  vla.len = n
  vla

template asOpenArray*[T](a: VarLenArray[T]): openarray[T] =
  toOpenArray(addr a.data[0],0,a.len-1)  #  addr first last

proc toSeq*[T](a: VarLenArray[T]): seq[T] =
  result = newSeq[T](len(a))
  for i in 0 ..< len(a) :
    result[i] = a[i]

iterator items*[T](a: VarLenArray[T]): T =
  for i in 0..<a.len:
    yield a[i]
