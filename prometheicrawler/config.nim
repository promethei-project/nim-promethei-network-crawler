import std/net
import std/sequtils
import pkg/chronicles
import pkg/libp2p
import pkg/prometheidht
import ./utils/version
import ./networkConfig

let doc =
  """
Promethei Network Crawler. Generates network metrics.

Usage:
  prometheicrawler [--logLevel=<l>] [--publicIp=<a>] [--metricsAddress=<ip>] [--metricsPort=<p>] [--dataDir=<dir>] [--discoveryPort=<p>] [--bootNodes=<n>] [--dhtEnable=<e>] [--stepDelay=<ms>] [--revisitDelay=<m>] [--checkDelay=<m>]  [--expiryDelay=<m>] [--marketplaceEnable=<e>] [--ethProvider=<a>] [--marketplaceAddress=<a>] [--requestCheckDelay=<m>] [--historyRangeSeconds=<s>]

Options:
  --logLevel=<l>                    Sets log level [default: INFO]
  --publicIp=<a>                    Public IP address where this instance is reachable.
  --metricsAddress=<ip>             Listen address of the metrics server [default: 0.0.0.0]
  --metricsPort=<p>                 Listen HTTP port of the metrics server [default: 8008]
  --dataDir=<dir>                   Directory for storing data [default: crawler_data]
  --discoveryPort=<p>               Port used for DHT [default: 8090]
  --bootNodes=<n>                   Optional override for bootstrap SPRs. Semi-colon-separated list.

  --dhtEnable=<e>                   Set to "1" to enable DHT crawler [default: 1]
  --stepDelay=<ms>                  Delay in milliseconds per node visit [default: 1000]
  --revisitDelay=<m>                Delay in minutes after which a node can be revisited [default: 60]
  --checkDelay=<m>                  Delay with which the 'revisitDelay' is checked for all known nodes [default: 10]
  --expiryDelay=<m>                 Delay in minutes after which unresponsive nodes are discarded [default: 1440] (24h)

  --marketplaceEnable=<e>           Set to "1" to enable marketplace metrics [default: 1]
  --ethProvider=<a>                 Optional override address including http(s) or ws of the eth provider
  --marketplaceAddress=<a>          Optional override Eth address of Promethei contracts deployment
  --requestCheckDelay=<m>           Delay in minutes after which storage contract status is (re)checked [default: 10]
  --historyRangeSeconds=<s>         Seconds of history to used when starting marketplace metrics. [default: 2592000]
"""

import strutils
import docopt

type Config* = ref object
  logLevel*: string
  publicIp*: string
  metricsAddress*: IpAddress
  metricsPort*: Port
  dataDir*: string
  discPort*: Port
  bootNodes*: seq[SignedPeerRecord]

  dhtEnable*: bool
  stepDelayMs*: int
  revisitDelayMins*: int
  checkDelayMins*: int
  expiryDelayMins*: int

  marketplaceEnable*: bool
  ethProvider*: string
  marketplaceAddress*: string
  requestCheckDelay*: int
  historyRangeSeconds*: int

proc `$`*(config: Config): string =
  "Crawler:" & " logLevel=" & config.logLevel & " publicIp=" & config.publicIp &
    " metricsAddress=" & $config.metricsAddress & " metricsPort=" & $config.metricsPort &
    " dataDir=" & config.dataDir & " discPort=" & $config.discPort & " dhtEnable=" &
    $config.dhtEnable & " bootNodes=" & config.bootNodes.mapIt($it).join(";") &
    " stepDelay=" & $config.stepDelayMs & " revisitDelayMins=" & $config.revisitDelayMins &
    " expiryDelayMins=" & $config.expiryDelayMins & " checkDelayMins=" &
    $config.checkDelayMins & " marketplaceEnable=" & $config.marketplaceEnable &
    " ethProvider=" & config.ethProvider & " marketplaceAddress=" &
    config.marketplaceAddress & " requestCheckDelay=" & $config.requestCheckDelay &
    " historyRangeSeconds=" & $config.historyRangeSeconds

proc stringToSpr(uri: string): SignedPeerRecord =
  var res: SignedPeerRecord
  try:
    if not res.fromURI(uri):
      warn "Invalid SignedPeerRecord uri", uri = uri
      quit QuitFailure
  except LPError as exc:
    warn "Invalid SignedPeerRecord uri", uri = uri, error = exc.msg
    quit QuitFailure
  except CatchableError as exc:
    warn "Invalid SignedPeerRecord uri", uri = uri, error = exc.msg
    quit QuitFailure
  res

proc toBootNodes(input: seq[string]): seq[SignedPeerRecord] =
  return input.mapIt(stringToSpr(it))

proc getEnable(input: string): bool =
  input == "1"

proc parseConfig*(): Config =
  let
    args = docopt(doc, version = crawlerFullVersion)
    networkConfig = getNetworkConfig()

  proc get(name: string): string =
    $args[name]

  proc getOrDefault(name: string, default: seq[string]): seq[string] =
    if args[name]:
      return get(name).split(";")
    return default

  proc getOrDefault(name: string, default: string): string =
    if args[name]:
      return get(name)
    return default

  return Config(
    logLevel: get("--logLevel"),
    publicIp: get("--publicIp"),
    metricsAddress: parseIpAddress(get("--metricsAddress")),
    metricsPort: Port(parseInt(get("--metricsPort"))),
    dataDir: get("--dataDir"),
    discPort: Port(parseInt(get("--discoveryPort"))),
    bootNodes: toBootNodes(getOrDefault("--bootNodes", networkConfig.spr.records)),
    dhtEnable: getEnable(get("--dhtEnable")),
    stepDelayMs: parseInt(get("--stepDelay")),
    revisitDelayMins: parseInt(get("--revisitDelay")),
    checkDelayMins: parseInt(get("--checkDelay")),
    expiryDelayMins: parseInt(get("--expiryDelay")),
    marketplaceEnable: getEnable(get("--marketplaceEnable")),
    ethProvider: getOrDefault("--ethProvider", networkConfig.team.utils.crawlerRpc),
    marketplaceAddress:
      getOrDefault("--marketplaceAddress", networkConfig.marketplace.contractAddress),
    requestCheckDelay: parseInt(get("--requestCheckDelay")),
    historyRangeSeconds: parseInt(get("--historyRangeSeconds")),
  )
