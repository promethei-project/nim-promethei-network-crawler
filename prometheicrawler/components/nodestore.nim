import std/os
import pkg/datastore
import pkg/datastore/typedds
import pkg/questionable/results
import pkg/chronicles
import pkg/chronos
import pkg/libp2p

import ../types
import ../component
import ../state
import ../utils/datastoreutils
import ../utils/asyncdataevent
import ../services/clock

const nodestoreName = "nodestore"

logScope:
  topics = "nodestore"

type
  NodeEntry* = object
    id*: Nid
    lastVisit*: uint64
    firstInactive*: uint64

  OnNodeEntry* = proc(item: NodeEntry): Future[?!void] {.async: (raises: []), gcsafe.}

  NodeStore* = ref object of Component
    state: State
    store: TypedDatastore
    clock: Clock
    subFound: AsyncDataEventSubscription
    subCheck: AsyncDataEventSubscription

proc `$`*(entry: NodeEntry): string =
  $entry.id & ":" & $entry.lastVisit & " " & $entry.firstInactive

proc toBytes*(entry: NodeEntry): seq[byte] =
  var buffer = initProtoBuffer()
  buffer.write(1, $entry.id)
  buffer.write(2, entry.lastVisit)
  buffer.write(3, entry.firstInactive)
  buffer.finish()
  return buffer.buffer

proc fromBytes*(_: type NodeEntry, data: openArray[byte]): ?!NodeEntry =
  var
    buffer = initProtoBuffer(data)
    idStr: string
    lastVisit: uint64
    firstInactive: uint64

  if buffer.getField(1, idStr).isErr:
    return failure("Unable to decode `idStr`")

  if buffer.getField(2, lastVisit).isErr:
    return failure("Unable to decode `lastVisit`")

  if buffer.getField(3, firstInactive).isErr:
    return failure("Unable to decode `firstInactive`")

  return success(
    NodeEntry(
      id: Nid.fromStr(idStr), lastVisit: lastVisit, firstInactive: firstInactive
    )
  )

proc encode*(e: NodeEntry): seq[byte] =
  e.toBytes()

proc decode*(T: type NodeEntry, bytes: seq[byte]): ?!T =
  try:
    if bytes.len < 1:
      return success(
        NodeEntry(id: Nid.fromStr("0"), lastVisit: 0.uint64, firstInactive: 0.uint64)
      )
    return NodeEntry.fromBytes(bytes)
  except ValueError as err:
    return failure(err.msg)

proc storeNodeIsNew(
    s: NodeStore, nid: Nid
): Future[?!bool] {.async: (raises: [CancelledError]).} =
  without key =? Key.init(nodestoreName / $nid), err:
    error "failed to format key", err = err.msg
    return failure(err)
  without exists =? (await s.store.has(key)), err:
    error "failed to check store for key", err = err.msg
    return failure(err)

  if not exists:
    let entry = NodeEntry(id: nid, lastVisit: 0, firstInactive: 0)
    ?await s.store.put(key, entry)
    info "New node", nodeId = $nid

  return success(not exists)

proc fireNewNodesDiscovered(
    s: NodeStore, nids: seq[Nid]
): Future[?!void] {.async: (raises: [CancelledError]).} =
  await s.state.events.newNodesDiscovered.fire(nids)

proc fireNodesDeleted(
    s: NodeStore, nids: seq[Nid]
): Future[?!void] {.async: (raises: []).} =
  await s.state.events.nodesDeleted.fire(nids)

proc processFoundNodes(
    s: NodeStore, nids: seq[Nid]
): Future[?!void] {.async: (raises: [CancelledError]).} =
  var newNodes = newSeq[Nid]()
  for nid in nids:
    without isNew =? (await s.storeNodeIsNew(nid)), err:
      return failure(err)
    if isNew:
      newNodes.add(nid)

  if newNodes.len > 0:
    trace "Discovered new nodes", newNodes = newNodes.len
    ?await s.fireNewNodesDiscovered(newNodes)
  return success()

proc processNodeCheck(
    s: NodeStore, event: DhtNodeCheckEventData
): Future[?!void] {.async: (raises: [CancelledError]).} =
  without key =? Key.init(nodestoreName / $(event.id)), err:
    error "failed to format key", err = err.msg
    return failure(err)

  without exists =? (await s.store.has(key)), err:
    error "failed to check store for key", err = err.msg
    return failure(err)

  if not exists:
    warn "Expected node entry to exist in store, but was not found.", key = $key
    # We treat the node as deleted, so it can be rediscovered and readded if it still exists in the network.
    ?await s.fireNodesDeleted(@[event.id])
    return success()

  without var entry =? (await get[NodeEntry](s.store, key)), err:
    error "failed to get entry for key", err = err.msg, key = $key
    return failure(err)

  entry.lastVisit = s.clock.now()
  if event.isOk and entry.firstInactive > 0:
    entry.firstInactive = 0
  elif not event.isOk and entry.firstInactive == 0:
    entry.firstInactive = s.clock.now()

  ?await s.store.put(key, entry)
  return success()

proc deleteEntry(
    s: NodeStore, nid: Nid
): Future[?!bool] {.async: (raises: [CancelledError]).} =
  without key =? Key.init(nodestoreName / $nid), err:
    error "failed to format key", err = err.msg
    return failure(err)
  without exists =? (await s.store.has(key)), err:
    error "failed to check store for key", err = err.msg, key = $key
    return failure(err)

  if exists:
    ?await s.store.delete(key)

  return success(exists)

method iterateAll*(
    s: NodeStore, onNode: OnNodeEntry
): Future[?!void] {.async: (raises: []), base.} =
  without queryKey =? Key.init(nodestoreName), err:
    error "failed to format key", err = err.msg
    return failure(err)
  try:
    without iter =? (await query[NodeEntry](s.store, Query.init(queryKey))), err:
      error "failed to create query", err = err.msg
      return failure(err)

    while not iter.finished:
      without item =? (await iter.next()), err:
        error "failure during query iteration", err = err.msg
        return failure(err)
      without value =? item.value, err:
        error "failed to get value from iterator", err = err.msg
        return failure(err)

      if $(value.id) == "0" and value.lastVisit == 0 and value.firstInactive == 0:
        # iterator stop entry
        discard
      else:
        ?await onNode(value)

      await sleepAsync(1.millis)
  except CatchableError as exc:
    return failure(exc.msg)

  return success()

method deleteEntries*(
    s: NodeStore, nids: seq[Nid]
): Future[?!void] {.async: (raises: []), base.} =
  var deleted = newSeq[Nid]()
  for nid in nids:
    try:
      without wasDeleted =? (await s.deleteEntry(nid)), err:
        return failure(err)
      if wasDeleted:
        deleted.add(nid)
    except CatchableError as exc:
      return failure(exc.msg)

  ?await s.fireNodesDeleted(deleted)
  return success()

method start*(s: NodeStore): Future[?!void] {.async: (raises: [CancelledError]).} =
  info "starting..."

  proc onNodesFound(
      nids: seq[Nid]
  ): Future[?!void] {.async: (raises: [CancelledError]).} =
    return await s.processFoundNodes(nids)

  proc onCheck(
      event: DhtNodeCheckEventData
  ): Future[?!void] {.async: (raises: [CancelledError]).} =
    return await s.processNodeCheck(event)

  s.subFound = s.state.events.nodesFound.subscribe(onNodesFound)
  s.subCheck = s.state.events.dhtNodeCheck.subscribe(onCheck)
  return success()

method stop*(s: NodeStore): Future[?!void] {.async: (raises: [CancelledError]).} =
  await s.state.events.nodesFound.unsubscribe(s.subFound)
  await s.state.events.dhtNodeCheck.unsubscribe(s.subCheck)
  return success()

proc new*(
    T: type NodeStore, state: State, store: TypedDatastore, clock: Clock
): NodeStore =
  NodeStore(state: state, store: store, clock: clock)

proc createNodeStore*(state: State, clock: Clock): ?!NodeStore =
  without ds =? createTypedDatastore(state.config.dataDir / "nodestore"), err:
    error "Failed to create typed datastore for node store", err = err.msg
    return failure(err)

  return success(NodeStore.new(state, ds, clock))
