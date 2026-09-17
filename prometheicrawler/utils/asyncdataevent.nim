import pkg/questionable
import pkg/questionable/results
import pkg/chronos

type
  AsyncDataEventSubscription* = ref object
    key: EventQueueKey
    listenFuture: Future[void]
    fireEvent: AsyncEvent
    lastResult: ?!void
    inHandler: bool
    delayedUnsubscribe: bool

  AsyncDataEvent*[T] = ref object
    queue: AsyncEventQueue[?T]
    subscriptions: seq[AsyncDataEventSubscription]

  AsyncDataEventHandler*[T] =
    proc(data: T): Future[?!void] {.gcsafe, async: (raises: [CancelledError]).}

proc newAsyncDataEvent*[T](): AsyncDataEvent[T] =
  AsyncDataEvent[T](
    queue: newAsyncEventQueue[?T](), subscriptions: newSeq[AsyncDataEventSubscription]()
  )

proc performUnsubscribe[T](
    event: AsyncDataEvent[T], subscription: AsyncDataEventSubscription
) {.async: (raises: [CancelledError]).} =
  if subscription in event.subscriptions:
    await subscription.listenFuture.cancelAndWait()
    event.subscriptions.delete(event.subscriptions.find(subscription))

proc subscribe*[T](
    event: AsyncDataEvent[T], handler: AsyncDataEventHandler[T]
): AsyncDataEventSubscription =
  var subscription = AsyncDataEventSubscription(
    key: event.queue.register(),
    listenFuture: newFuture[void](),
    fireEvent: newAsyncEvent(),
    inHandler: false,
    delayedUnsubscribe: false,
  )

  proc listener() {.async: (raises: [CancelledError]).} =
    try:
      while true:
        let items = await event.queue.waitEvents(subscription.key)
        for item in items:
          if data =? item:
            subscription.inHandler = true
            subscription.lastResult = (await handler(data))
            subscription.inHandler = false
        subscription.fireEvent.fire()
    except AsyncEventQueueFullError as err:
      raiseAssert("AsyncEventQueueFullError in asyncdataevent.listener()")

  subscription.listenFuture = listener()

  event.subscriptions.add(subscription)
  subscription

proc fire*[T](
    event: AsyncDataEvent[T], data: T
): Future[?!void] {.async: (raises: []).} =
  event.queue.emit(data.some)
  var toUnsubscribe = newSeq[AsyncDataEventSubscription]()
  for sub in event.subscriptions:
    try:
      await sub.fireEvent.wait()
      sub.fireEvent.clear()
    except CancelledError:
      discard
    if err =? sub.lastResult.errorOption:
      return failure(err)
    if sub.delayedUnsubscribe:
      toUnsubscribe.add(sub)

  for sub in toUnsubscribe:
    try:
      await event.unsubscribe(sub)
    except CatchableError as exc:
      return failure(exc.msg)

  success()

proc unsubscribe*[T](
    event: AsyncDataEvent[T], subscription: AsyncDataEventSubscription
) {.async: (raises: [CancelledError]).} =
  if subscription.inHandler:
    subscription.delayedUnsubscribe = true
  else:
    await event.performUnsubscribe(subscription)

proc unsubscribeAll*[T](
    event: AsyncDataEvent[T]
) {.async: (raises: [CancelledError]).} =
  let all = event.subscriptions
  for subscription in all:
    await event.unsubscribe(subscription)

proc listeners*[T](event: AsyncDataEvent[T]): int =
  event.subscriptions.len
