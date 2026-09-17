import std/random
import std/typetraits
import pkg/stint
import pkg/stew/byteutils
import ../../prometheicrawler/types

proc example*[T: SomeInteger](_: type T): T =
  rand(T)

proc example*[T, N](_: type array[N, T]): array[N, T] =
  for item in result.mitems:
    item = T.example

proc example*(_: type UInt256): UInt256 =
  UInt256.fromBytes(array[32, byte].example)

proc example*[T: distinct](_: type T): T =
  type baseType = T.distinctBase
  T(baseType.example)

proc genNid*(): Nid =
  Nid(rand(uint64).u256)

proc genRid*(): Rid =
  Rid(array[32, byte].example)
