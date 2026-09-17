import pkg/chronos
import pkg/questionable
import pkg/questionable/results
import pkg/asynctest/chronos/unittest
import std/sequtils
import std/options

import ../../../prometheicrawler/components/chaincrawler
import ../../../prometheicrawler/services/marketplace/market
import ../../../prometheicrawler/types
import ../../../prometheicrawler/state
import ../mocks/mockstate
import ../mocks/mockrequeststore
import ../mocks/mockmarketplace
import ../helpers

suite "ChainCrawler":
  var
    state: MockState
    store: MockRequestStore
    marketplace: MockMarketplaceService
    crawler: ChainCrawler

  setup:
    state = createMockState()
    store = createMockRequestStore()
    marketplace = createMockMarketplaceService()

    crawler = ChainCrawler.new(state, store, marketplace)
    (await crawler.start()).tryGet()

  teardown:
    state.checkAllUnsubscribed()

  test "start should subscribe to new requests":
    check:
      marketplace.subNewRequestsCallback.isSome()

  test "new-request subscription should add requestId to store":
    let rid = genRid()
    (await (marketplace.subNewRequestsCallback.get())(rid)).tryGet()

    check:
      store.addRid == rid

  test "start should iterate past requests and add then to store":
    check:
      marketplace.iterRequestsCallback.isSome()

    let rid = genRid()
    (await marketplace.iterRequestsCallback.get()(rid)).tryGet()

    check:
      store.addRid == rid
