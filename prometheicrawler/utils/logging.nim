import std/strutils
import std/typetraits

import pkg/chronicles
import pkg/chronicles/helpers
import pkg/chronicles/topics_registry

proc updateLogLevel*(logLevel: string) =
  notice "Updating logLevel", logLevel
  let directives = logLevel.split(";")
  try:
    setLogLevel(LogLevel.TRACE) #parseEnum[LogLevel](directives[0].toUpperAscii))
  except ValueError:
    notice "valueerror logLevel", logLevel
    raise (ref ValueError)(
      msg:
        "Please specify one of: trace, debug, " & "info, notice, warn, error or fatal"
    )

  if directives.len > 1:
    for topicName, settings in parseTopicDirectives(directives[1 ..^ 1]):
      if not setTopicState(topicName, settings.state, settings.logLevel):
        warn "Unrecognized logging topic", topic = topicName
