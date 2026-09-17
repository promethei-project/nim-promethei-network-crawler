import pkg/chronos
import pkg/questionable/results
import pkg/asynctest/chronos/unittest

import ../../../prometheicrawler/components/timetracker
import ../../../prometheicrawler/components/nodestore
import ../../../prometheicrawler/utils/asyncdataevent
import ../../../prometheicrawler/types
import ../../../prometheicrawler/state
import ../mocks/mockstate
import ../mocks/mocknodestore
import ../mocks/mockdht
import ../mocks/mockclock
import ../helpers

suite "TimeTracker":
  let now = 123456789.uint64

  var
    nid: Nid
    state: MockState
    store: MockNodeStore
    clock: MockClock
    dht: MockDht
    time: TimeTracker
    nodesToRevisitReceived: seq[Nid]
    sub: AsyncDataEventSubscription

  setup:
    nid = genNid()
    state = createMockState()
    store = createMockNodeStore()
    clock = createMockClock()
    dht = createMockDht()

    clock.setNow = now

    # Subscribe to nodesToRevisit event
    nodesToRevisitReceived = newSeq[Nid]()
    proc onToRevisit(
        nids: seq[Nid]
    ): Future[?!void] {.async: (raises: [CancelledError]).} =
      nodesToRevisitReceived = nids
      return success()

    sub = state.events.nodesToRevisit.subscribe(onToRevisit)

    state.config.checkDelayMins = 11
    state.config.expiryDelayMins = 22

    time = TimeTracker.new(state, store, dht, clock)
    (await time.start()).tryGet()

  teardown:
    await state.events.nodesToRevisit.unsubscribe(sub)
    state.checkAllUnsubscribed()

  proc onStepCheck() {.async: (raises: []).} =
    try:
      (await state.steppers[0]()).tryGet()
    except CatchableError:
      raiseAssert("CatchableError in onStepCheck")

  proc onStepRt() {.async: (raises: []).} =
    try:
      (await state.steppers[1]()).tryGet()
    except CatchableError:
      raiseAssert("CatchableError in onStepRt")

  proc createNodeInStore(lastVisit: uint64, firstInactive = 0.uint64): Nid =
    let entry =
      NodeEntry(id: genNid(), lastVisit: lastVisit, firstInactive: firstInactive)
    store.nodesToIterate.add(entry)
    return entry.id

  test "start sets steppers for check and routingtable load":
    check:
      state.delays[0] == state.config.checkDelayMins.minutes
      state.delays[1] == 30.minutes

  test "onStep fires nodesToRevisit event for nodes past revisit timestamp":
    let
      revisitTimestamp = now - ((state.config.revisitDelayMins + 1) * 60).uint64
      revisitNodeId = createNodeInStore(revisitTimestamp)

    await onStepCheck()

    check:
      revisitNodeId in nodesToRevisitReceived

  test "onStep does not fire nodesToRevisit event for nodes that are recent":
    let
      recentTimestamp = now - ((state.config.revisitDelayMins - 1) * 60).uint64
      recentNodeId = createNodeInStore(recentTimestamp)

    await onStepCheck()

    check:
      recentNodeId notin nodesToRevisitReceived

  test "onStep deletes nodes with past expired inactivity timestamp":
    let
      expiredTimestamp = now - ((state.config.expiryDelayMins + 1) * 60).uint64
      expiredNodeId = createNodeInStore(now, expiredTimestamp)

    await onStepCheck()

    check:
      expiredNodeId in store.nodesToDelete

  test "onStep does not delete nodes with recent inactivity timestamp":
    let
      recentTimestamp = now - ((state.config.expiryDelayMins - 1) * 60).uint64
      recentNodeId = createNodeInStore(now, recentTimestamp)

    await onStepCheck()

    check:
      recentNodeId notin store.nodesToDelete

  test "onStep does not delete nodes with zero inactivity timestamp":
    let activeNodeId = createNodeInStore(now, 0.uint64)

    await onStepCheck()

    check:
      activeNodeId notin store.nodesToDelete

  test "onStep raises routingTable nodes as nodesFound":
    var nodesFound = newSeq[Nid]()
    proc onNodesFound(
        nids: seq[Nid]
    ): Future[?!void] {.async: (raises: [CancelledError]).} =
      nodesFound = nids
      return success()

    let sub = state.events.nodesFound.subscribe(onNodesFound)

    dht.routingTable.add(nid)

    await onStepRt()

    check:
      nid in nodesFound

    await state.events.nodesFound.unsubscribe(sub)
