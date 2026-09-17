import pkg/asynctest/chronos/unittest
import ../../../prometheicrawler/state
import ../../../prometheicrawler/utils/asyncdataevent
import ../../../prometheicrawler/types
import ../../../prometheicrawler/config

type MockState* = ref object of State
  steppers*: seq[OnStep]
  delays*: seq[Duration]

proc checkAllUnsubscribed*(s: MockState) =
  check:
    s.events.nodesFound.listeners == 0
    s.events.newNodesDiscovered.listeners == 0
    s.events.dhtNodeCheck.listeners == 0
    s.events.nodesToRevisit.listeners == 0

method whileRunning*(
    s: MockState, step: OnStep, delay: Duration
) {.async: (raises: []).} =
  s.steppers.add(step)
  s.delays.add(delay)

proc createMockState*(): MockState =
  MockState(
    status: ApplicationStatus.Running,
    config: Config(dhtEnable: true, marketplaceEnable: true, requestCheckDelay: 4),
    events: Events(
      nodesFound: newAsyncDataEvent[seq[Nid]](),
      newNodesDiscovered: newAsyncDataEvent[seq[Nid]](),
      dhtNodeCheck: newAsyncDataEvent[DhtNodeCheckEventData](),
      nodesToRevisit: newAsyncDataEvent[seq[Nid]](),
      nodesDeleted: newAsyncDataEvent[seq[Nid]](),
    ),
    steppers: newSeq[OnStep](),
    delays: newSeq[Duration](),
  )
