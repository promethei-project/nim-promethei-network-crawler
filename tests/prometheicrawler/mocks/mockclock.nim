import ../../../prometheicrawler/services/clock

type MockClock* = ref object of Clock
  setNow*: uint64

method now*(clock: MockClock): uint64 {.raises: [].} =
  clock.setNow

proc createMockClock*(): MockClock =
  MockClock(setNow: 12)
