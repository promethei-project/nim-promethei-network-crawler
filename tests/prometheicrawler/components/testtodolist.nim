import pkg/chronos
import pkg/questionable/results
import pkg/asynctest/chronos/unittest

import ../../../prometheicrawler/components/todolist
import ../../../prometheicrawler/utils/asyncdataevent
import ../../../prometheicrawler/types
import ../../../prometheicrawler/state
import ../mocks/mockstate
import ../mocks/mockmetrics
import ../helpers

suite "TodoList":
  var
    nid: Nid
    state: MockState
    metrics: MockMetrics
    todo: TodoList

  setup:
    nid = genNid()
    state = createMockState()
    metrics = createMockMetrics()

    todo = TodoList.new(state, metrics)
    (await todo.awake()).tryGet()

  teardown:
    (await todo.stop()).tryGet()
    state.checkAllUnsubscribed()

  proc fireNewNodesDiscoveredEvent(nids: seq[Nid]) {.async: (raises: []).} =
    try:
      (await state.events.newNodesDiscovered.fire(nids)).tryGet()
    except CatchableError:
      raiseAssert("CatchableError in fireNewNodesDiscoveredEvent")

  proc fireNodesToRevisitEvent(nids: seq[Nid]) {.async: (raises: []).} =
    try:
      (await state.events.nodesToRevisit.fire(nids)).tryGet()
    except CatchableError:
      raiseAssert("CatchableError in fireNodesToRevisitEvent")

  test "discovered nodes are added to todo list":
    await fireNewNodesDiscoveredEvent(@[nid])
    let item = (await todo.pop).tryGet()

    check:
      item == nid

  test "revisit nodes are added to todo list":
    await fireNodesToRevisitEvent(@[nid])
    let item = (await todo.pop).tryGet()

    check:
      item == nid

  test "newNodesDiscovered event updates todo metric":
    await fireNewNodesDiscoveredEvent(@[nid])

    check:
      metrics.todo == 1

  test "nodesToRevisit event updates todo metric":
    await fireNodesToRevisitEvent(@[nid])

    check:
      metrics.todo == 1

  test "does not store duplicates":
    await fireNewNodesDiscoveredEvent(@[nid])
    await fireNodesToRevisitEvent(@[nid])

    check:
      metrics.todo == 1

  test "pop on empty todo list waits until item is added":
    let popFuture = todo.pop()
    check:
      not popFuture.finished

    await fireNewNodesDiscoveredEvent(@[nid])

    check:
      popFuture.finished
      popFuture.value.tryGet() == nid

  test "pop updates todo metric":
    await fireNewNodesDiscoveredEvent(@[nid])

    discard (await todo.pop()).tryGet()

    check:
      metrics.todo == 0
