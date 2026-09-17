import pkg/ethers
import pkg/questionable

import ../../../prometheicrawler/services/marketplace
import ../../../prometheicrawler/types

logScope:
  topics = "marketplace"

type MockMarketplaceService* = ref object of MarketplaceService
  subNewRequestsCallback*: ?OnNewRequest
  iterRequestsCallback*: ?OnNewRequest
  requestInfoReturns*: ?RequestInfo
  requestInfoRid*: Rid

method subscribeToNewRequests*(
    m: MockMarketplaceService, onNewRequest: OnNewRequest
): Future[?!void] {.async: (raises: []).} =
  m.subNewRequestsCallback = some(onNewRequest)
  return success()

method iteratePastNewRequestEvents*(
    m: MockMarketplaceService, onNewRequest: OnNewRequest
): Future[?!void] {.async: (raises: []).} =
  m.iterRequestsCallback = some(onNewRequest)
  return success()

method getRequestInfo*(
    m: MockMarketplaceService, rid: Rid
): Future[?RequestInfo] {.async: (raises: []).} =
  m.requestInfoRid = rid
  return m.requestInfoReturns

proc createMockMarketplaceService*(): MockMarketplaceService =
  MockMarketplaceService(
    subNewRequestsCallback: none(OnNewRequest), iterRequestsCallback: none(OnNewRequest)
  )
