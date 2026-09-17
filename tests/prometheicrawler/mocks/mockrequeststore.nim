import pkg/questionable/results
import pkg/chronos

import ../../../prometheicrawler/components/requeststore
import ../../../prometheicrawler/types

type MockRequestStore* = ref object of RequestStore
  addRid*: Rid
  removeRid*: Rid
  iterateEntries*: seq[RequestEntry]

method add*(s: MockRequestStore, rid: Rid): Future[?!void] {.async: (raises: []).} =
  s.addRid = rid
  return success()

method remove*(s: MockRequestStore, rid: Rid): Future[?!void] {.async: (raises: []).} =
  s.removeRid = rid
  return success()

method iterateAll*(
    s: MockRequestStore, onNode: OnRequestEntry
): Future[?!void] {.async: (raises: []).} =
  for entry in s.iterateEntries:
    ?await onNode(entry)
  return success()

proc createMockRequestStore*(): MockRequestStore =
  MockRequestStore(iterateEntries: newSeq[RequestEntry]())
