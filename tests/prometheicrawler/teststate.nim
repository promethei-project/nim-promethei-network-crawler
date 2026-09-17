import pkg/chronos
import pkg/questionable/results
import pkg/asynctest/chronos/unittest

import ../../prometheicrawler/state
import ../../prometheicrawler/config
import ../../prometheicrawler/types
import ../../prometheicrawler/utils/asyncdataevent

suite "State":
  var state: State

  setup:
    state = State(
      status: ApplicationStatus.Running,
      config: Config(),
      events: Events(
        nodesFound: newAsyncDataEvent[seq[Nid]](),
        newNodesDiscovered: newAsyncDataEvent[seq[Nid]](),
        dhtNodeCheck: newAsyncDataEvent[DhtNodeCheckEventData](),
        nodesToRevisit: newAsyncDataEvent[seq[Nid]](),
      ),
    )

  test "whileRunning":
    var counter = 0

    proc onStep(): Future[?!void] {.async: (raises: []), gcsafe.} =
      inc counter
      return success()

    await state.whileRunning(onStep, 1.milliseconds)

    while counter < 5:
      await sleepAsync(1.milliseconds)

    state.status = ApplicationStatus.Stopped

    await sleepAsync(10.milliseconds)

    check:
      counter == 5
