import pkg/chronicles
import pkg/chronos
import pkg/questionable
import pkg/questionable/results

import ../services/dht
import ./todolist
import ../config
import ../types
import ../component
import ../state
import ../utils/asyncdataevent

logScope:
  topics = "dhtcrawler"

type DhtCrawler* = ref object of Component
  state: State
  dht: Dht
  todo: TodoList

proc raiseCheckEvent(
    c: DhtCrawler, nid: Nid, success: bool
): Future[?!void] {.async: (raises: []).} =
  let event = DhtNodeCheckEventData(id: nid, isOk: success)
  if err =? (await c.state.events.dhtNodeCheck.fire(event)).errorOption:
    error "failed to raise check event", err = err.msg
    return failure(err)
  return success()

proc step(c: DhtCrawler): Future[?!void] {.async: (raises: []).} =
  without nid =? (await c.todo.pop()), err:
    error "failed to pop todolist", err = err.msg
    return failure(err)

  without response =? await c.dht.getNeighbors(nid), err:
    error "failed to get neighbors", err = err.msg
    return failure(err)

  if err =? (await c.raiseCheckEvent(nid, response.isResponsive)).errorOption:
    return failure(err)

  if err =? (await c.state.events.nodesFound.fire(response.nodeIds)).errorOption:
    error "failed to raise nodesFound event", err = err.msg
    return failure(err)

  return success()

method start*(c: DhtCrawler): Future[?!void] {.async: (raises: [CancelledError]).} =
  info "starting..."

  proc onStep(): Future[?!void] {.async: (raises: []), gcsafe.} =
    await c.step()

  if c.state.config.dhtEnable:
    try:
      await c.state.whileRunning(onStep, c.state.config.stepDelayMs.milliseconds)
    except CatchableError as err:
      return failure(err.msg)

  return success()

proc new*(T: type DhtCrawler, state: State, dht: Dht, todo: TodoList): DhtCrawler =
  DhtCrawler(state: state, dht: dht, todo: todo)
