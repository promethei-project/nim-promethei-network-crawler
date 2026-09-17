import pkg/chronicles
import pkg/metrics
import pkg/metrics/chronos_httpserver

declareGauge(todoNodesGauge, "DHT nodes to be visited")
declareGauge(okNodesGauge, "DHT nodes successfully contacted")
declareGauge(nokNodesGauge, "DHT nodes failed to contact")

declareGauge(requestsGauge, "Marketplace active storage requests")
declareGauge(pendingGauge, "Marketplace pending storage requests")
declareGauge(requestSlotsGauge, "Marketplace active storage request slots")
declareGauge(
  totalStorageSizeGauge, "Marketplace total bytes stored in active storage requests"
)
declareGauge(
  totalPriceGauge,
  "Marketplace total price per byte per second of all active storage requests",
)

type
  OnUpdateMetric = proc(value: int64): void {.gcsafe, raises: [].}

  Metrics* = ref object of RootObj
    todoNodes: OnUpdateMetric
    okNodes: OnUpdateMetric
    nokNodes: OnUpdateMetric

    onRequests: OnUpdateMetric
    onPending: OnUpdateMetric
    onRequestSlots: OnUpdateMetric
    onTotalSize: OnUpdateMetric
    onPrice: OnUpdateMetric

proc startServer(metricsAddress: IpAddress, metricsPort: Port) =
  let metricsAddress = metricsAddress
  notice "Starting metrics HTTP server",
    url = "http://" & $metricsAddress & ":" & $metricsPort & "/metrics"
  try:
    startMetricsHttpServer($metricsAddress, metricsPort)
  except CatchableError as exc:
    raiseAssert exc.msg
  except Exception as exc:
    raiseAssert exc.msg # TODO fix metrics

method setTodoNodes*(m: Metrics, value: int) {.base, gcsafe, raises: [].} =
  m.todoNodes(value.int64)

method setOkNodes*(m: Metrics, value: int) {.base, gcsafe, raises: [].} =
  m.okNodes(value.int64)

method setNokNodes*(m: Metrics, value: int) {.base, gcsafe, raises: [].} =
  m.nokNodes(value.int64)

method setRequests*(m: Metrics, value: int) {.base, gcsafe, raises: [].} =
  m.onRequests(value.int64)

method setPendingRequests*(m: Metrics, value: int) {.base, gcsafe, raises: [].} =
  m.onPending(value.int64)

method setRequestSlots*(m: Metrics, value: int) {.base, gcsafe, raises: [].} =
  m.onRequestSlots(value.int64)

method setTotalSize*(m: Metrics, value: int64) {.base, gcsafe, raises: [].} =
  m.onTotalSize(value.int64)

method setPrice*(m: Metrics, value: int64) {.base, gcsafe, raises: [].} =
  m.onPrice(value.int64)

proc createMetrics*(metricsAddress: IpAddress, metricsPort: Port): Metrics =
  startServer(metricsAddress, metricsPort)

  # We can't extract this into a function because gauges cannot be passed as argument.
  # The use of global state in nim-metrics is not pleasant.
  proc onTodo(value: int64) =
    todoNodesGauge.set(value)

  proc onOk(value: int64) =
    okNodesGauge.set(value)

  proc onNok(value: int64) =
    nokNodesGauge.set(value)

  proc onRequests(value: int64) =
    requestsGauge.set(value)

  proc onPending(value: int64) =
    pendingGauge.set(value)

  proc onRequestSlots(value: int64) =
    requestSlotsGauge.set(value)

  proc onTotalSize(value: int64) =
    totalStorageSizeGauge.set(value)

  proc onPrice(value: int64) =
    totalPriceGauge.set(value)

  return Metrics(
    todoNodes: onTodo,
    okNodes: onOk,
    nokNodes: onNok,
    onRequests: onRequests,
    onPending: onPending,
    onRequestSlots: onRequestSlots,
    onTotalSize: onTotalSize,
    onPrice: onPrice,
  )
