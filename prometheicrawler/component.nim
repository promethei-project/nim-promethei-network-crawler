import pkg/chronos
import pkg/questionable/results

type Component* = ref object of RootObj

method awake*(
    c: Component
): Future[?!void] {.async: (raises: [CancelledError]), base.} =
  # Awake is called on all components in an unspecified order.
  # Use this method to subscribe/connect to other components.
  return success()

method start*(
    c: Component
): Future[?!void] {.async: (raises: [CancelledError]), base.} =
  # Start is called on all components in an unspecified order.
  # It is guaranteed that all components have already successfulled handled 'awake'.
  # Use this method to begin the work of this component.
  return success()

method stop*(c: Component): Future[?!void] {.async: (raises: [CancelledError]), base.} =
  # Use this method to stop, unsubscribe, and clean up any resources.
  return success()
