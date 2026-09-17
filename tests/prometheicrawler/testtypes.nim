import pkg/chronos
import pkg/asynctest/chronos/unittest
import pkg/questionable/results

import ../../prometheicrawler/types
import ./helpers

suite "Types":
  test "nid string encoding":
    let
      nid = genNid()
      str = $nid

    check:
      nid == Nid.fromStr(str)

  test "nid byte encoding":
    let
      nid = genNid()
      bytes = nid.toBytes()

    check:
      nid == Nid.fromBytes(bytes).tryGet()
