import pkg/chronos
import pkg/questionable/results
import pkg/asynctest/chronos/unittest

import ../../../prometheicrawler/components/dhtmetrics
import ../../../prometheicrawler/utils/asyncdataevent
import ../../../prometheicrawler/types
import ../../../prometheicrawler/state
import ../mocks/mockstate
import ../mocks/mocklist
import ../mocks/mockmetrics
import ../helpers

suite "DhtMetrics":
  var
    nid: Nid
    state: MockState
    okList: MockList
    nokList: MockList
    metrics: MockMetrics
    dhtmetrics: DhtMetrics

  setup:
    nid = genNid()
    state = createMockState()
    okList = createMockList()
    nokList = createMockList()
    metrics = createMockMetrics()

    dhtmetrics = DhtMetrics.new(state, okList, nokList, metrics)
    (await dhtmetrics.awake()).tryGet()
    (await dhtmetrics.start()).tryGet()

  teardown:
    (await dhtmetrics.stop()).tryGet()
    state.checkAllUnsubscribed()

  proc fireDhtNodeCheckEvent(isOk: bool) {.async: (raises: []).} =
    let event = DhtNodeCheckEventData(id: nid, isOk: isOk)
    try:
      (await state.events.dhtNodeCheck.fire(event)).tryGet()
    except CatchableError:
      raiseAssert("CatchableError in fireDhtNodeCheckEvent")

  proc fireNodesDeletedEvent(nids: seq[Nid]) {.async: (raises: []).} =
    try:
      (await state.events.nodesDeleted.fire(nids)).tryGet()
    except CatchableError:
      raiseAssert("CatchableError in fireNodesDeletedEvent")

  test "dhtmetrics start should load both lists":
    check:
      okList.loadCalled
      nokList.loadCalled

  test "dhtNodeCheck event should add node to okList if check is successful":
    await fireDhtNodeCheckEvent(true)

    check:
      nid in okList.added

  test "dhtNodeCheck event should add node to nokList if check has failed":
    await fireDhtNodeCheckEvent(false)

    check:
      nid in nokList.added

  test "dhtNodeCheck event should remove node from nokList if check is successful":
    await fireDhtNodeCheckEvent(true)

    check:
      nid in nokList.removed

  test "dhtNodeCheck event should remove node from okList if check has failed":
    await fireDhtNodeCheckEvent(false)

    check:
      nid in okList.removed

  test "dhtNodeCheck event should set okList length as dht-ok metric":
    let length = 123

    okList.length = length

    await fireDhtNodeCheckEvent(true)

    check:
      metrics.ok == length

  test "dhtNodeCheck event should set nokList length as dht-nok metric":
    let length = 234

    nokList.length = length

    await fireDhtNodeCheckEvent(true)

    check:
      metrics.nok == length

  test "nodesDeleted event should remove node from both lists":
    await fireNodesDeletedEvent(@[nid])

    check:
      nid in okList.removed
      nid in nokList.removed

  test "nodesDeleted event should set list lengths as metrics for both lists":
    okList.length = 123
    nokList.length = 345

    await fireNodesDeletedEvent(@[nid])

    check:
      metrics.ok == okList.length
      metrics.nok == nokList.length
