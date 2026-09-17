import pkg/chronicles

import ./prometheicrawler/application

when defined(posix):
  import system/ansi_c

when isMainModule:
  let app = Application()

  # Stopping code must be in scope of app declaration.
  # Else capture of the instance is not allowed due to {.noconv.}.
  proc onStopSignal() =
    app.stop()
    notice "Stopping Crawler..."

  proc controlCHandler() {.noconv.} =
    when defined(windows):
      # workaround for https://github.com/nim-lang/Nim/issues/4057
      try:
        setupForeignThreadGc()
      except Exception as exc:
        raiseAssert exc.msg
    notice "Shutting down after having received SIGINT"
    onStopSignal()

  try:
    setControlCHook(controlCHandler)
  except Exception as exc:
    warn "Cannot set ctrl-c handler", msg = exc.msg

  when defined(posix):
    proc SIGTERMHandler(signal: cint) {.noconv.} =
      notice "Shutting down after having received SIGTERM"
      onStopSignal()

    c_signal(ansi_c.SIGTERM, SIGTERMHandler)

  app.run()
