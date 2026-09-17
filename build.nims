mode = ScriptMode.Verbose

import std/os except commandLineParams

### Helper functions
proc buildBinary(name: string, srcDir = "./", params = "", lang = "c") =
  if not dirExists "build":
    mkDir "build"

  # allow something like "nim nimbus --verbosity:0 --hints:off nimbus.nims"
  var extra_params = params
  when compiles(commandLineParams):
    for param in commandLineParams():
      extra_params &= " " & param
  else:
    for i in 2 ..< paramCount():
      extra_params &= " " & paramStr(i)

  let
    # Place build output in 'build' folder, even if name includes a longer path.
    outName = os.lastPathPart(name)
    cmd =
      "nim " & lang & " --out:build/" & outName & " " & extra_params & " " & srcDir &
      name & ".nim"

  exec(cmd)

proc test(name: string, srcDir = "tests/", params = "", lang = "c") =
  buildBinary name, srcDir, params
  exec "build/" & name

task prometheicrawler, "build prometheicrawler binary":
  buildBinary "prometheicrawler",
    params = "-d:chronicles_runtime_filtering -d:chronicles_log_level=TRACE"

task testPrometheicrawler, "Build & run Promethei Crawler tests":
  test "testPrometheiCrawler"

task build, "build promethei crawler binary":
  prometheiCrawlerTask()

task test, "Run tests":
  testPrometheiCrawlerTask()
