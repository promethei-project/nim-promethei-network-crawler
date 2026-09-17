import pkg/chronos
import pkg/questionable/results

import ./state
import ./services/clock
import ./services/metrics
import ./services/dht

import ./services/marketplace

import ./component
import ./components/dhtcrawler
import ./components/timetracker
import ./components/nodestore
import ./components/dhtmetrics
import ./components/todolist
import ./components/chainmetrics
import ./components/chaincrawler
import ./components/requeststore

proc createComponents*(
    state: State
): Future[?!seq[Component]] {.async: (raises: [CancelledError]).} =
  var components: seq[Component] = newSeq[Component]()
  let clock = createClock()

  without dht =? (await createDht(state)), err:
    return failure(err)

  without nodeStore =? createNodeStore(state, clock), err:
    return failure(err)

  without requestStore =? createRequestStore(state), err:
    return failure(err)

  let
    metrics = createMetrics(state.config.metricsAddress, state.config.metricsPort)
    todoList = createTodoList(state, metrics)
    marketplace = createMarketplace(state, clock)
    chainMetrics = ChainMetrics.new(state, metrics, requestStore, marketplace)

  without dhtMetrics =? createDhtMetrics(state, metrics), err:
    return failure(err)

  components.add(dht)
  components.add(todoList)
  components.add(nodeStore)
  components.add(DhtCrawler.new(state, dht, todoList))
  components.add(TimeTracker.new(state, nodeStore, dht, clock))
  components.add(dhtMetrics)
  components.add(marketplace)
  components.add(chainMetrics)
  components.add(ChainCrawler.new(state, requestStore, marketplace))

  return success(components)
