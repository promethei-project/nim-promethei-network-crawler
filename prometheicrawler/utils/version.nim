import std/strutils

proc getCrawlerVersion(): string =
  let tag = strip(staticExec("git tag"))
  if tag.isEmptyOrWhitespace:
    return "untagged build"
  return tag

proc getCrawlerRevision(): string =
  # using a slice in a static context breaks nimsuggest for some reason
  var res = strip(staticExec("git rev-parse --short HEAD"))
  return res

proc getNimBanner(): string =
  staticExec("nim --version | grep Version")

const
  crawlerVersion* = getCrawlerVersion()
  crawlerRevision* = getCrawlerRevision()
  nimBanner* = getNimBanner()

  crawlerFullVersion* =
    "PrometheiNetworkCrawler version:  " & crawlerVersion & "\p" &
    "PrometheiNetworkCrawler revision: " & crawlerRevision & "\p" & nimBanner
