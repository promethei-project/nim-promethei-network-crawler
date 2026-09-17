import std/os
import pkg/chronos
import pkg/questionable/results
import pkg/asynctest/chronos/unittest
import pkg/datastore/typedds

import ../../../prometheicrawler/components/nodestore
import ../../../prometheicrawler/utils/datastoreutils
import ../../../prometheicrawler/utils/asyncdataevent
import ../../../prometheicrawler/types
import ../../../prometheicrawler/state
import ../mocks/mockstate
import ../mocks/mockclock
import ../helpers

suite "Nodestore":
  let
    dsPath = getTempDir() / "testds"
    nodestoreName = "nodestore"

  var
    ds: TypedDatastore
    state: MockState
    clock: MockClock
    store: NodeStore

  setup:
    ds = createTypedDatastore(dsPath).tryGet()
    state = createMockState()
    clock = createMockClock()

    store = NodeStore.new(state, ds, clock)
    (await store.start()).tryGet()

  teardown:
    (await store.stop()).tryGet()
    (await ds.close()).tryGet()
    state.checkAllUnsubscribed()
    removeDir(dsPath)

  proc fireNodeFoundEvent(nids: seq[Nid]) {.async: (raises: []).} =
    try:
      (await state.events.nodesFound.fire(nids)).tryGet()
    except CatchableError:
      raiseAssert("CatchableError in fireNodeFoundEvent")

  proc fireCheckEvent(nid: Nid, isOk: bool) {.async: (raises: []).} =
    try:
      (await state.events.dhtNodeCheck.fire(DhtNodeCheckEventData(id: nid, isOk: isOk))).tryGet()
    except CatchableError:
      raiseAssert("CatchableError in fireCheckEvent")

  test "nodeEntry encoding":
    let entry =
      NodeEntry(id: genNid(), lastVisit: 123.uint64, firstInactive: 234.uint64)

    let
      bytes = entry.encode()
      decoded = NodeEntry.decode(bytes).tryGet()

    check:
      entry.id == decoded.id
      entry.lastVisit == decoded.lastVisit
      entry.firstInactive == decoded.firstInactive

  test "nodesFound event should store nodes":
    let
      nid = genNid()
      expectedKey = Key.init(nodestoreName / $nid).tryGet()

    await fireNodeFoundEvent(@[nid])

    check:
      (await ds.has(expectedKey)).tryGet()

    let entry = (await get[NodeEntry](ds, expectedKey)).tryGet()
    check:
      entry.id == nid

  test "nodesFound event should fire newNodesDiscovered":
    var newNodes = newSeq[Nid]()
    proc onNewNodes(
        nids: seq[Nid]
    ): Future[?!void] {.async: (raises: [CancelledError]).} =
      newNodes = nids
      return success()

    let
      sub = state.events.newNodesDiscovered.subscribe(onNewNodes)
      nid = genNid()

    await fireNodeFoundEvent(@[nid])

    check:
      newNodes == @[nid]

    await state.events.newNodesDiscovered.unsubscribe(sub)

  test "nodesFound event should not fire newNodesDiscovered for previously seen nodes":
    let nid = genNid()

    # Make nid known first. Then subscribe.
    await fireNodeFoundEvent(@[nid])

    var
      newNodes = newSeq[Nid]()
      count = 0
    proc onNewNodes(
        nids: seq[Nid]
    ): Future[?!void] {.async: (raises: [CancelledError]).} =
      newNodes = nids
      inc count
      return success()

    let sub = state.events.newNodesDiscovered.subscribe(onNewNodes)

    # Firing the event again should not trigger newNodesDiscovered for nid
    await fireNodeFoundEvent(@[nid])

    check:
      newNodes.len == 0
      count == 0

    await state.events.newNodesDiscovered.unsubscribe(sub)

  test "iterateAll yields all known nids":
    let
      nid1 = genNid()
      nid2 = genNid()
      nid3 = genNid()

    await fireNodeFoundEvent(@[nid1, nid2, nid3])

    var iterNodes = newSeq[Nid]()
    proc onNode(entry: NodeEntry): Future[?!void] {.async: (raises: []), gcsafe.} =
      iterNodes.add(entry.id)
      return success()

    (await store.iterateAll(onNode)).tryGet()

    check:
      nid1 in iterNodes
      nid2 in iterNodes
      nid3 in iterNodes

  test "iterateAll yields no uninitialized entries":
    let
      nid1 = genNid()
      nid2 = genNid()
      nid3 = genNid()

    await fireNodeFoundEvent(@[nid1, nid2, nid3])

    var iterNodes = newSeq[Nid]()
    proc onNode(entry: NodeEntry): Future[?!void] {.async: (raises: []), gcsafe.} =
      iterNodes.add(entry.id)
      return success()

    (await store.iterateAll(onNode)).tryGet()

    for nid in iterNodes:
      check:
        $nid != "0"

  test "deleteEntries deletes entries":
    let
      nid1 = genNid()
      nid2 = genNid()
      nid3 = genNid()

    await fireNodeFoundEvent(@[nid1, nid2, nid3])
    (await store.deleteEntries(@[nid1, nid2])).tryGet()

    var iterNodes = newSeq[Nid]()
    proc onNode(entry: NodeEntry): Future[?!void] {.async: (raises: []), gcsafe.} =
      iterNodes.add(entry.id)
      return success()

    (await store.iterateAll(onNode)).tryGet()

    check:
      nid1 notin iterNodes
      nid2 notin iterNodes
      nid3 in iterNodes

  test "deleteEntries fires nodesDeleted event":
    var deletedNodes = newSeq[Nid]()
    proc onDeleted(
        nids: seq[Nid]
    ): Future[?!void] {.async: (raises: [CancelledError]).} =
      deletedNodes = nids
      return success()

    let
      sub = state.events.nodesDeleted.subscribe(onDeleted)
      nid1 = genNid()
      nid2 = genNid()
      nid3 = genNid()

    await fireNodeFoundEvent(@[nid1, nid2, nid3])
    (await store.deleteEntries(@[nid1, nid2])).tryGet()

    check:
      nid1 in deletedNodes
      nid2 in deletedNodes
      nid3 notin deletedNodes

    await state.events.nodesDeleted.unsubscribe(sub)

  test "dhtNodeCheck event should update lastVisit":
    let
      nid = genNid()
      expectedKey = Key.init(nodestoreName / $nid).tryGet()

    clock.setNow = 123456789.uint64

    await fireNodeFoundEvent(@[nid])

    let originalEntry = (await get[NodeEntry](ds, expectedKey)).tryGet()
    check:
      originalEntry.lastVisit == 0

    await fireCheckEvent(nid, true)

    let updatedEntry = (await get[NodeEntry](ds, expectedKey)).tryGet()
    check:
      clock.setNow == updatedEntry.lastVisit

  test "failed dhtNodeCheck event should set firstInactive":
    let
      nid = genNid()
      expectedKey = Key.init(nodestoreName / $nid).tryGet()

    clock.setNow = 345345.uint64

    await fireNodeFoundEvent(@[nid])
    await fireCheckEvent(nid, false)

    let updatedEntry = (await get[NodeEntry](ds, expectedKey)).tryGet()
    check:
      clock.setNow == updatedEntry.firstInactive

  test "successful dhtNodeCheck event should clear firstInactive":
    let
      nid = genNid()
      expectedKey = Key.init(nodestoreName / $nid).tryGet()

    clock.setNow = 456456.uint64

    await fireNodeFoundEvent(@[nid])
    await fireCheckEvent(nid, false)
    await fireCheckEvent(nid, true)

    let updatedEntry = (await get[NodeEntry](ds, expectedKey)).tryGet()
    check:
      updatedEntry.firstInactive == 0

  test "dhtNodeCheck event for non-existing node should fire nodesDeleted":
    var deletedNodes = newSeq[Nid]()
    proc onDeleted(
        nids: seq[Nid]
    ): Future[?!void] {.async: (raises: [CancelledError]).} =
      deletedNodes = nids
      return success()

    let
      sub = state.events.nodesDeleted.subscribe(onDeleted)
      nid = genNid()

    # We don't fire nodeFound first. So the store doesn't know it exists.
    await fireCheckEvent(nid, true)

    check:
      nid in deletedNodes

    await state.events.nodesDeleted.unsubscribe(sub)
