import pkg/chronos
import pkg/chronicles
import pkg/questionable/results

import ./config
import ./utils/asyncdataevent
import ./types

logScope:
  topics = "state"

type
  OnStep* = proc(): Future[?!void] {.async: (raises: []), gcsafe.}

  DhtNodeCheckEventData* = object
    id*: Nid
    isOk*: bool

  Events* = ref object
    nodesFound*: AsyncDataEvent[seq[Nid]]
    newNodesDiscovered*: AsyncDataEvent[seq[Nid]]
    dhtNodeCheck*: AsyncDataEvent[DhtNodeCheckEventData]
    nodesToRevisit*: AsyncDataEvent[seq[Nid]]
    nodesDeleted*: AsyncDataEvent[seq[Nid]]

  ApplicationStatus* {.pure.} = enum
    Stopped
    Stopping
    Running

  State* = ref object of RootObj
    status*: ApplicationStatus
    config*: Config
    events*: Events

proc delayedWorkerStart(
    s: State, step: OnStep, delay: Duration
) {.async: (raises: [CancelledError]).} =
  await sleepAsync(1.seconds)

  proc worker(): Future[void] {.async: (raises: [CancelledError]).} =
    while s.status == ApplicationStatus.Running:
      if err =? (await step()).errorOption:
        error "Failure-result caught in main loop. Stopping...", err = err.msg
        s.status = ApplicationStatus.Stopping
      await sleepAsync(delay)

  asyncSpawn worker()

method whileRunning*(
    s: State, step: OnStep, delay: Duration
) {.async: (raises: []), base.} =
  # We use a small delay before starting the workers because 'whileRunning' is likely called from
  # component 'start' methods, which are executed sequentially in arbitrary order (to prevent temporal coupling).
  # Worker steps might start raising events that other components haven't had time to subscribe to yet.
  asyncSpawn s.delayedWorkerStart(step, delay)
