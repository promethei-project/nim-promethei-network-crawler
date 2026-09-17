import pkg/chronicles
import pkg/chronos
import pkg/questionable/results

import ./nodestore
import ../services/dht
import ../services/clock
import ../component
import ../state
import ../types
import ../utils/asyncdataevent

logScope:
  topics = "timetracker"

type TimeTracker* = ref object of Component
  state: State
  nodestore: NodeStore
  dht: Dht
  clock: Clock

proc checkRevisitsAndExpiry(t: TimeTracker): Future[?!void] {.async: (raises: []).} =
  let
    revisitThreshold = t.clock.now() - (t.state.config.revisitDelayMins * 60).uint64
    expiryThreshold = t.clock.now() - (t.state.config.expiryDelayMins * 60).uint64

  var
    toRevisit = newSeq[Nid]()
    toDelete = newSeq[Nid]()

  proc checkNode(item: NodeEntry): Future[?!void] {.async: (raises: []), gcsafe.} =
    if item.lastVisit < revisitThreshold:
      toRevisit.add(item.id)
    if item.firstInactive > 0 and item.firstInactive < expiryThreshold:
      toDelete.add(item.id)
    return success()

  ?await t.nodestore.iterateAll(checkNode)

  if toRevisit.len > 0:
    trace "Found nodes to revisit", toRevisit = toRevisit.len
    ?await t.state.events.nodesToRevisit.fire(toRevisit)

  if toDelete.len > 0:
    trace "Found expired node records to delete", toDelete = toDelete.len
    ?await t.nodestore.deleteEntries(toDelete)

  return success()

proc raiseRoutingTableNodes(t: TimeTracker): Future[?!void] {.async: (raises: []).} =
  let nids = t.dht.getRoutingTableNodeIds()
  trace "Raising routing table nodes", nodes = nids.len

  if err =? (await t.state.events.nodesFound.fire(nids)).errorOption:
    error "failed to raise nodesFound event", err = err.msg
    return failure(err)
  return success()

method start*(t: TimeTracker): Future[?!void] {.async: (raises: [CancelledError]).} =
  info "starting..."

  proc onCheckRevisitAndExpiry(): Future[?!void] {.async: (raises: []), gcsafe.} =
    await t.checkRevisitsAndExpiry()

  proc onRoutingTable(): Future[?!void] {.async: (raises: []), gcsafe.} =
    await t.raiseRoutingTableNodes()

  await t.state.whileRunning(
    onCheckRevisitAndExpiry, t.state.config.checkDelayMins.minutes
  )
  await t.state.whileRunning(onRoutingTable, 30.minutes)
  return success()

proc new*(
    T: type TimeTracker, state: State, nodestore: NodeStore, dht: Dht, clock: Clock
): TimeTracker =
  TimeTracker(state: state, nodestore: nodestore, dht: dht, clock: clock)
