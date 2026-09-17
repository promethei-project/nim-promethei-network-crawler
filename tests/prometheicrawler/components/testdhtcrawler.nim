import pkg/chronos
import pkg/questionable
import pkg/questionable/results
import pkg/asynctest/chronos/unittest

import ../../../prometheicrawler/components/dhtcrawler
import ../../../prometheicrawler/services/dht
import ../../../prometheicrawler/utils/asyncdataevent
import ../../../prometheicrawler/types
import ../../../prometheicrawler/state
import ../mocks/mockstate
import ../mocks/mockdht
import ../mocks/mocktodolist
import ../helpers

suite "DhtCrawler":
  var
    nid1: Nid
    nid2: Nid
    state: MockState
    todo: MockTodoList
    dht: MockDht
    crawler: DhtCrawler

  setup:
    nid1 = genNid()
    nid2 = genNid()
    state = createMockState()
    todo = createMockTodoList()
    dht = createMockDht()

    crawler = DhtCrawler.new(state, dht, todo)
    (await crawler.start()).tryGet()

  teardown:
    state.checkAllUnsubscribed()

  proc onStep() {.async: (raises: []).} =
    try:
      (await state.steppers[0]()).tryGet()
    except CatchableError:
      raiseAssert("CatchableError in onStep")

  proc responsive(nid: Nid): GetNeighborsResponse =
    GetNeighborsResponse(isResponsive: true, nodeIds: @[nid])

  proc unresponsive(nid: Nid): GetNeighborsResponse =
    GetNeighborsResponse(isResponsive: false, nodeIds: @[nid])

  test "onStep should pop a node from the todoList and getNeighbors for it":
    todo.popReturn = success(nid1)
    dht.getNeighborsReturn = success(responsive(nid1))

    await onStep()

    check:
      !(dht.getNeighborsArg) == nid1

  test "onStep is not activated when config.dhtEnable is false":
    # Recreate crawler, reset mockstate:
    state.steppers = @[]
    # disable DHT:
    state.config.dhtEnable = false
    (await crawler.start()).tryGet()

    todo.popReturn = success(nid1)
    dht.getNeighborsReturn = success(responsive(nid1))

    check:
      state.steppers.len == 0

  test "nodes returned by getNeighbors are raised as nodesFound":
    var nodesFound = newSeq[Nid]()
    proc onNodesFound(
        nids: seq[Nid]
    ): Future[?!void] {.async: (raises: [CancelledError]).} =
      nodesFound = nids
      return success()

    let sub = state.events.nodesFound.subscribe(onNodesFound)

    todo.popReturn = success(nid1)
    dht.getNeighborsReturn = success(responsive(nid2))

    await onStep()

    check:
      nid2 in nodesFound

    await state.events.nodesFound.unsubscribe(sub)

  test "responsive result from getNeighbors raises the node as successful dhtNodeCheck":
    var checkEvent = DhtNodeCheckEventData()
    proc onCheck(
        event: DhtNodeCheckEventData
    ): Future[?!void] {.async: (raises: [CancelledError]).} =
      checkEvent = event
      return success()

    let sub = state.events.dhtNodeCheck.subscribe(onCheck)

    todo.popReturn = success(nid1)
    dht.getNeighborsReturn = success(responsive(nid2))

    await onStep()

    check:
      checkEvent.id == nid1
      checkEvent.isOk == true

    await state.events.dhtNodeCheck.unsubscribe(sub)

  test "unresponsive result from getNeighbors raises the node as unsuccessful dhtNodeCheck":
    var checkEvent = DhtNodeCheckEventData()
    proc onCheck(
        event: DhtNodeCheckEventData
    ): Future[?!void] {.async: (raises: [CancelledError]).} =
      checkEvent = event
      return success()

    let sub = state.events.dhtNodeCheck.subscribe(onCheck)

    todo.popReturn = success(nid1)
    dht.getNeighborsReturn = success(unresponsive(nid2))

    await onStep()

    check:
      checkEvent.id == nid1
      checkEvent.isOk == false

    await state.events.dhtNodeCheck.unsubscribe(sub)
