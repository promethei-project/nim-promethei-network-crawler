import pkg/ethers
import pkg/questionable
import pkg/upraises
import ./marketplace/market
import ./marketplace/marketplace
import ../config
import ../component
import ../state
import ../types
import ./clock

logScope:
  topics = "marketplace"

type
  MarketplaceService* = ref object of Component
    state: State
    market: ?OnChainMarket
    clock: Clock

  OnNewRequest* = proc(id: Rid): Future[?!void] {.async: (raises: []), gcsafe.}
  RequestInfo* = ref object
    pending*: bool
    finished*: bool
    slots*: uint64
    slotSize*: uint64
    pricePerBytePerSecond*: uint64

proc notStarted() =
  raiseAssert("MarketplaceService was called before it was started.")

proc fetchRequestInfo(
    market: OnChainMarket, rid: Rid
): Future[?RequestInfo] {.async: (raises: []).} =
  try:
    let request = await market.getRequest(rid)
    if r =? request:
      let price = r.ask.pricePerBytePerSecond.u256.truncate(uint64)
      return some(
        RequestInfo(
          pending: false,
          finished: false,
          slots: r.ask.slots,
          slotSize: r.ask.slotSize,
          pricePerBytePerSecond: price,
        )
      )
  except CatchableError as exc:
    trace "Failed to get request info", err = exc.msg
  return none(RequestInfo)

method subscribeToNewRequests*(
    m: MarketplaceService, onNewRequest: OnNewRequest
): Future[?!void] {.async: (raises: []), base.} =
  proc resultWrapper(rid: Rid): Future[void] {.async: (raises: [CancelledError]).} =
    let response = await onNewRequest(rid)
    if error =? response.errorOption:
      raiseAssert("Error result in handling of onNewRequest callback: " & error.msg)

  proc onRequest(
      requestId: RequestId, ask: StorageAsk, expiry: StorageTimestamp
  ) {.raises: [].} =
    asyncSpawn resultWrapper(Rid(requestId))

  if market =? m.market:
    try:
      discard await market.subscribeRequests(onRequest)
      return success()
    except CatchableError as exc:
      return failure(exc.msg)
  else:
    notStarted()

method iteratePastNewRequestEvents*(
    m: MarketplaceService, onNewRequest: OnNewRequest
): Future[?!void] {.async: (raises: []), base.} =
  let
    timespan = m.state.config.historyRangeSeconds
    startTime = m.clock.now() - timespan.uint64

  if market =? m.market:
    try:
      let requests =
        await market.queryPastStorageRequestedEventsFromTime(startTime.int64)
      for request in requests:
        if error =? (await onNewRequest(Rid(request.requestId))).errorOption:
          return failure(error.msg)
      return success()
    except CatchableError as exc:
      return failure(exc.msg)
  else:
    notStarted()

method getRequestInfo*(
    m: MarketplaceService, rid: Rid
): Future[?RequestInfo] {.async: (raises: []), base.} =
  # If the request id exists and is running, fetch the request object and return the info object.
  # If the request is not found but the call to look it up was successful, return it as finished.
  # otherwise, return none.
  if market =? m.market:
    try:
      let state = await market.requestState(rid)
      if s =? state:
        if s == RequestState.New:
          return some(RequestInfo(pending: true, finished: false))
        if s == RequestState.Started:
          return await market.fetchRequestInfo(rid)
        else:
          return some(RequestInfo(pending: false, finished: true))
      else:
        # Received an "Marketplace_UnknownRequest" so this one is finished
        # We don't want to track it any more.
        return some(RequestInfo(pending: false, finished: true))
    except CatchableError as exc:
      trace "Failed to get request state", err = exc.msg
    return none(RequestInfo)
  else:
    notStarted()

method awake*(
    m: MarketplaceService
): Future[?!void] {.async: (raises: [CancelledError]).} =
  try:
    let provider = await JsonRpcProvider.connect(m.state.config.ethProvider)
    without marketplaceAddress =? Address.init(m.state.config.marketplaceAddress):
      return failure("Invalid MarketplaceAddress provided")

    let marketplace = MarketplaceContract.new(marketplaceAddress, provider)
    m.market = some(OnChainMarket.new(marketplace))
    return success()
  except JsonRpcProviderError as err:
    return failure(err.msg)

proc new(T: type MarketplaceService, state: State, clock: Clock): MarketplaceService =
  return MarketplaceService(state: state, market: none(OnChainMarket), clock: clock)

proc createMarketplace*(state: State, clock: Clock): MarketplaceService =
  return MarketplaceService.new(state, clock)
