import pkg/chronos
import pkg/questionable
import pkg/questionable/results
import pkg/asynctest/chronos/unittest

import ../../../prometheicrawler/utils/asyncdataevent

type ExampleData = object
  s: string

suite "AsyncDataEvent":
  var event: AsyncDataEvent[ExampleData]
  let msg = "Yeah!"

  setup:
    event = newAsyncDataEvent[ExampleData]()

  teardown:
    await event.unsubscribeAll()

  test "Successful event":
    var data = ""
    proc eventHandler(
        e: ExampleData
    ): Future[?!void] {.async: (raises: [CancelledError]).} =
      data = e.s
      success()

    let s = event.subscribe(eventHandler)

    check:
      isOK(await event.fire(ExampleData(s: msg)))
      data == msg

    await event.unsubscribe(s)

  test "Multiple events":
    var counter = 0
    proc eventHandler(
        e: ExampleData
    ): Future[?!void] {.async: (raises: [CancelledError]).} =
      inc counter
      success()

    let s = event.subscribe(eventHandler)

    check:
      isOK(await event.fire(ExampleData(s: msg)))
      isOK(await event.fire(ExampleData(s: msg)))
      isOK(await event.fire(ExampleData(s: msg)))

      counter == 3

    await event.unsubscribe(s)

  test "Multiple subscribers":
    var
      data1 = ""
      data2 = ""
      data3 = ""
    proc eventHandler1(
        e: ExampleData
    ): Future[?!void] {.async: (raises: [CancelledError]).} =
      data1 = e.s
      success()

    proc eventHandler2(
        e: ExampleData
    ): Future[?!void] {.async: (raises: [CancelledError]).} =
      data2 = e.s
      success()

    proc eventHandler3(
        e: ExampleData
    ): Future[?!void] {.async: (raises: [CancelledError]).} =
      data3 = e.s
      success()

    let
      sub1 = event.subscribe(eventHandler1)
      sub2 = event.subscribe(eventHandler2)
      sub3 = event.subscribe(eventHandler3)

    check:
      isOK(await event.fire(ExampleData(s: msg)))
      data1 == msg
      data2 == msg
      data3 == msg

    await event.unsubscribe(sub1)
    await event.unsubscribe(sub2)
    await event.unsubscribe(sub3)

  test "Failed event preserves error message":
    proc eventHandler(
        e: ExampleData
    ): Future[?!void] {.async: (raises: [CancelledError]).} =
      failure(msg)

    let s = event.subscribe(eventHandler)
    let fireResult = await event.fire(ExampleData(s: "a"))

    check:
      fireResult.isErr
      fireResult.error.msg == msg

    await event.unsubscribe(s)

  test "Emits data to multiple subscribers":
    var
      data1 = ""
      data2 = ""
      data3 = ""

    proc handler1(
        e: ExampleData
    ): Future[?!void] {.async: (raises: [CancelledError]).} =
      data1 = e.s
      success()

    proc handler2(
        e: ExampleData
    ): Future[?!void] {.async: (raises: [CancelledError]).} =
      data2 = e.s
      success()

    proc handler3(
        e: ExampleData
    ): Future[?!void] {.async: (raises: [CancelledError]).} =
      data3 = e.s
      success()

    let
      s1 = event.subscribe(handler1)
      s2 = event.subscribe(handler2)
      s3 = event.subscribe(handler3)

    let fireResult = await event.fire(ExampleData(s: msg))

    check:
      fireResult.isOK
      data1 == msg
      data2 == msg
      data3 == msg

    await event.unsubscribe(s1)
    await event.unsubscribe(s2)
    await event.unsubscribe(s3)

  test "Can fire and event without subscribers":
    check:
      isOK(await event.fire(ExampleData(s: msg)))

  test "Can unsubscribe in handler":
    proc doNothing() {.async: (raises: [CancelledError]), closure.} =
      await sleepAsync(1.millis)

    var callback = doNothing

    proc eventHandler(
        e: ExampleData
    ): Future[?!void] {.async: (raises: [CancelledError]).} =
      await callback()
      success()

    let s = event.subscribe(eventHandler)

    proc doUnsubscribe() {.async: (raises: [CancelledError]).} =
      await event.unsubscribe(s)

    callback = doUnsubscribe

    check:
      isOK(await event.fire(ExampleData(s: msg)))

    await event.unsubscribe(s)
