import ../../../prometheicrawler/services/metrics

type MockMetrics* = ref object of Metrics
  todo*: int
  ok*: int
  nok*: int
  requests*: int
  pending*: int
  slots*: int
  totalSize*: int64
  totalPrice*: int64

method setTodoNodes*(m: MockMetrics, value: int) =
  m.todo = value

method setOkNodes*(m: MockMetrics, value: int) =
  m.ok = value

method setNokNodes*(m: MockMetrics, value: int) =
  m.nok = value

method setRequests*(m: MockMetrics, value: int) =
  m.requests = value

method setPendingRequests*(m: MockMetrics, value: int) =
  m.pending = value

method setRequestSlots*(m: MockMetrics, value: int) =
  m.slots = value

method setTotalSize*(m: MockMetrics, value: int64) =
  m.totalSize = value

method setPrice*(m: MockMetrics, value: int64) =
  m.totalPrice = value

proc createMockMetrics*(): MockMetrics =
  MockMetrics()
