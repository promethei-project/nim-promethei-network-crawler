import pkg/chronicles
import pkg/chronos
import pkg/questionable
import pkg/questionable/results

import ../list
import ../state
import ../types
import ../services/metrics
import ../component
import ../utils/asyncdataevent

logScope:
  topics = "dhtmetrics"

type DhtMetrics* = ref object of Component
  state: State
  ok: List
  nok: List
  subCheck: AsyncDataEventSubscription
  subDel: AsyncDataEventSubscription
  metrics: Metrics

proc updateMetrics(d: DhtMetrics) =
  d.metrics.setOkNodes(d.ok.len)
  d.metrics.setNokNodes(d.nok.len)

proc handleCheckEvent(
    d: DhtMetrics, event: DhtNodeCheckEventData
): Future[?!void] {.async: (raises: [CancelledError]).} =
  if event.isOk:
    ?await d.ok.add(event.id)
    ?await d.nok.remove(event.id)
  else:
    ?await d.ok.remove(event.id)
    ?await d.nok.add(event.id)

  d.updateMetrics()
  return success()

proc handleDeleteEvent(
    d: DhtMetrics, nids: seq[Nid]
): Future[?!void] {.async: (raises: [CancelledError]).} =
  for nid in nids:
    ?await d.ok.remove(nid)
    ?await d.nok.remove(nid)
  d.updateMetrics()
  return success()

method awake*(d: DhtMetrics): Future[?!void] {.async: (raises: [CancelledError]).} =
  proc onCheck(
      event: DhtNodeCheckEventData
  ): Future[?!void] {.async: (raises: [CancelledError]).} =
    await d.handleCheckEvent(event)

  proc onDelete(nids: seq[Nid]): Future[?!void] {.async: (raises: [CancelledError]).} =
    await d.handleDeleteEvent(nids)

  d.subCheck = d.state.events.dhtNodeCheck.subscribe(onCheck)
  d.subDel = d.state.events.nodesDeleted.subscribe(onDelete)
  return success()

method start*(d: DhtMetrics): Future[?!void] {.async: (raises: [CancelledError]).} =
  info "starting..."
  ?await d.ok.load()
  ?await d.nok.load()
  return success()

method stop*(d: DhtMetrics): Future[?!void] {.async: (raises: [CancelledError]).} =
  await d.state.events.dhtNodeCheck.unsubscribe(d.subCheck)
  await d.state.events.nodesDeleted.unsubscribe(d.subDel)
  return success()

proc new*(
    T: type DhtMetrics, state: State, okList: List, nokList: List, metrics: Metrics
): DhtMetrics =
  DhtMetrics(state: state, ok: okList, nok: nokList, metrics: metrics)

proc createDhtMetrics*(state: State, metrics: Metrics): ?!DhtMetrics =
  without okList =? createList(state.config.dataDir, "dhtok"), err:
    return failure(err)
  without nokList =? createList(state.config.dataDir, "dhtnok"), err:
    return failure(err)

  success(DhtMetrics.new(state, okList, nokList, metrics))
