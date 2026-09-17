import std/os
import pkg/chronos
import pkg/questionable/results
import pkg/asynctest/chronos/unittest
import pkg/datastore/typedds

import ../../../prometheicrawler/components/requeststore
import ../../../prometheicrawler/utils/datastoreutils
import ../../../prometheicrawler/types
import ../../../prometheicrawler/state
import ../mocks/mockstate
import ../helpers

suite "Requeststore":
  let
    dsPath = getTempDir() / "testds"
    requeststoreName = "requeststore"

  var
    ds: TypedDatastore
    state: MockState
    store: RequestStore

  setup:
    ds = createTypedDatastore(dsPath).tryGet()
    state = createMockState()

    store = RequestStore.new(state, ds)

  teardown:
    (await ds.close()).tryGet()
    state.checkAllUnsubscribed()
    removeDir(dsPath)

  test "requestEntry encoding":
    let entry = RequestEntry(id: genRid())

    let
      bytes = entry.encode()
      decoded = RequestEntry.decode(bytes).tryGet()

    check:
      entry.id == decoded.id

  test "add stores a new requestId":
    let rid = genRid()
    (await store.add(rid)).tryGet()

    let
      key = Key.init(requeststoreName / $rid).tryGet()
      stored = (await get[RequestEntry](ds, key)).tryGet()

    check:
      stored.id == rid

  test "remove will remove an entry":
    let rid = genRid()
    (await store.add(rid)).tryGet()
    (await store.remove(rid)).tryGet()

    let
      key = Key.init(requeststoreName / $rid).tryGet()
      isStored = (await ds.has(key)).tryGet()

    check:
      isStored == false

  test "iterateAll yields all entries":
    let
      rid1 = genRid()
      rid2 = genRid()
      rid3 = genRid()

    (await store.add(rid1)).tryGet()
    (await store.add(rid2)).tryGet()
    (await store.add(rid3)).tryGet()

    var entries = newSeq[RequestEntry]()
    proc onEntry(entry: RequestEntry): Future[?!void] {.async: (raises: []), gcsafe.} =
      entries.add(entry)
      return success()

    (await store.iterateAll(onEntry)).tryGet()

    check:
      entries.len == 3

    let
      ids = @[entries[0].id, entries[1].id, entries[2].id]
      all = @[rid1, rid2, rid3]

    for id in ids:
      check:
        id in all

    for id in all:
      check:
        id in ids
