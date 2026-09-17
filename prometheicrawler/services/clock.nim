import std/times

type Clock* = ref object of RootObj

method now*(clock: Clock): uint64 {.base, gcsafe, raises: [].} =
  let now = times.now().utc
  now.toTime().toUnix().uint64

proc createClock*(): Clock =
  Clock()
