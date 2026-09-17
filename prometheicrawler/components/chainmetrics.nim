import pkg/chronicles
import pkg/chronos
import pkg/questionable
import pkg/questionable/results

import ../state
import ../services/metrics
import ../services/marketplace
import ../components/requeststore
import ../component
import ../types

logScope:
  topics = "chainmetrics"

type
  ChainMetrics* = ref object of Component
    state: State
    metrics: Metrics
    store: RequestStore
    marketplace: MarketplaceService

  Update = ref object
    numRequests: int
    numPending: int
    numSlots: int
    totalSize: int64
    totalPrice: uint64

proc collectUpdate(c: ChainMetrics): Future[?!Update] {.async: (raises: []).} =
  var update = Update(
    numRequests: 0, numPending: 0, numSlots: 0, totalSize: 0, totalPrice: 0.uint64
  )

  proc onRequest(entry: RequestEntry): Future[?!void] {.async: (raises: []).} =
    inc update.numRequests

    let response = await c.marketplace.getRequestInfo(entry.id)
    if info =? response:
      if info.pending:
        trace "request is pending", id = $entry.id
        inc update.numPending
      else:
        if info.finished:
          trace "request has finished", id = $entry.id
          ?await c.store.remove(entry.id)
        else:
          trace "request is running", id = $entry.id
          update.numSlots += info.slots.int
          update.totalSize += (info.slots * info.slotSize).int64
          update.totalPrice += info.pricePerBytePerSecond
    return success()

  ?await c.store.iterateAll(onRequest)
  return success(update)

proc updateMetrics(c: ChainMetrics, update: Update) =
  c.metrics.setRequests(update.numRequests)
  c.metrics.setPendingRequests(update.numPending)
  c.metrics.setRequestSlots(update.numSlots)
  c.metrics.setTotalSize(update.totalSize)
  c.metrics.setPrice(update.totalPrice.int64)

proc step(c: ChainMetrics): Future[?!void] {.async: (raises: []).} =
  without update =? (await c.collectUpdate()), err:
    return failure(err)

  c.updateMetrics(update)
  return success()

method start*(c: ChainMetrics): Future[?!void] {.async: (raises: [CancelledError]).} =
  info "starting..."

  proc onStep(): Future[?!void] {.async: (raises: []), gcsafe.} =
    return await c.step()

  if c.state.config.marketplaceEnable:
    await c.state.whileRunning(onStep, c.state.config.requestCheckDelay.minutes)

  return success()

proc new*(
    T: type ChainMetrics,
    state: State,
    metrics: Metrics,
    store: RequestStore,
    marketplace: MarketplaceService,
): ChainMetrics =
  ChainMetrics(state: state, metrics: metrics, store: store, marketplace: marketplace)
