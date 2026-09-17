import std/sequtils
import pkg/questionable/results
import pkg/chronos

import ../../../prometheicrawler/components/nodestore
import ../../../prometheicrawler/types

type MockNodeStore* = ref object of NodeStore
  nodesToIterate*: seq[NodeEntry]
  nodesToDelete*: seq[Nid]

method iterateAll*(
    s: MockNodeStore, onNode: OnNodeEntry
): Future[?!void] {.async: (raises: []).} =
  for node in s.nodesToIterate:
    ?await onNode(node)
  return success()

method deleteEntries*(
    s: MockNodeStore, nids: seq[Nid]
): Future[?!void] {.async: (raises: []).} =
  s.nodesToDelete = nids
  return success()

proc createMockNodeStore*(): MockNodeStore =
  MockNodeStore(nodesToIterate: newSeq[NodeEntry](), nodesToDelete: newSeq[Nid]())
