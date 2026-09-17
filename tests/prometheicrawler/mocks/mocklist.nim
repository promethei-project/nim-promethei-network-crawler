import pkg/chronos
import pkg/questionable/results

import ../../../prometheicrawler/types
import ../../../prometheicrawler/list

type MockList* = ref object of List
  loadCalled*: bool
  added*: seq[Nid]
  addSuccess*: bool
  removed*: seq[Nid]
  removeSuccess*: bool
  length*: int

method load*(this: MockList): Future[?!void] {.async: (raises: [CancelledError]).} =
  this.loadCalled = true
  return success()

method add*(
    this: MockList, nid: Nid
): Future[?!void] {.async: (raises: [CancelledError]).} =
  this.added.add(nid)
  if this.addSuccess:
    return success()
  return failure("test failure")

method remove*(
    this: MockList, nid: Nid
): Future[?!void] {.async: (raises: [CancelledError]).} =
  this.removed.add(nid)
  if this.removeSuccess:
    return success()
  return failure("test failure")

method len*(this: MockList): int =
  return this.length

proc createMockList*(): MockList =
  MockList(
    loadCalled: false,
    added: newSeq[Nid](),
    addSuccess: true,
    removed: newSeq[Nid](),
    removeSuccess: true,
    length: 0,
  )
