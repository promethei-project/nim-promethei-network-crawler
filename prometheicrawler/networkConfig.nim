import std/envvars
import std/httpclient
import std/sequtils

import pkg/chronicles
import pkg/serde/json
import pkg/questionable
import pkg/questionable/results

logScope:
  topics = "networkconfig"

# Endpoint types
type
  NetworkConfig* = object
    latest* {.serialize.}: string
    sprs* {.serialize.}: seq[PrometheiSprEntry]
    marketplace* {.serialize.}: seq[PrometheiMarketplaceEntry]
    team* {.serialize.}: PrometheiNetworkTeamObject

  PrometheiSprEntry* = object
    supportedVersions* {.serialize.}: seq[string]
    records* {.serialize.}: seq[string]

  PrometheiMarketplaceEntry* = object
    supportedVersions* {.serialize.}: seq[string]
    contractAddress* {.serialize.}: string

  PrometheiNetworkTeamObject* = object
    utils* {.serialize.}: PrometheiNetworkTeamUtilsObject

  PrometheiNetworkTeamUtilsObject* = object
    crawlerRpc* {.serialize.}: string
    botRpc* {.serialize.}: string
    elasticSearch* {.serialize.}: string

# Application types
type
  PrometheiNetwork* = object
    spr*: PrometheiSprEntry
    marketplace*: PrometheiMarketplaceEntry
    team*: TeamObject

  TeamObject* = object
    utils*: PrometheiNetworkTeamUtilsObject

# Connector
const EnvVarNetwork = "PROMETHEI_NETWORK"
const EnvVarVersion = "PROMETHEI_VERSION"
const EnvVarConfigUrl = "PROMETHEI_CONFIG_URL"
const EnvVarConfigFile = "PROMETHEI_CONFIG_FILE"

proc getEnvOrDefault(key: string, default: string): string =
  return getEnv(key, default)

proc fetchModelFromFile(file: string): string =
  trace "Loading model from file", file
  return readFile(file)

proc getFetchUrl(): string =
  let overrideUrl = getEnvOrDefault(EnvVarConfigUrl, "")
  if overrideUrl.len > 0:
    return overrideUrl

  let network = getEnvOrDefault(EnvVarNetwork, "testnet")
  return "http://config.archivist.storage/" & network & ".json"

proc fetchModelFromUrl(): string =
  let
    url = getFetchUrl()
    client = newHttpClient()
  try:
    trace "Loading model form URL", url
    return client.getContent(url)
  finally:
    client.close()

proc fetchModelJson(): string =
  let overrideFile = getEnvOrDefault(EnvVarConfigFile, "")
  if overrideFile.len > 0:
    return fetchModelFromFile(overrideFile)
  return fetchModelFromUrl()

proc fetchModel(): NetworkConfig =
  let str = fetchModelJson()
  return tryGet(NetworkConfig.fromJson(str))

proc getVersion(fullModel: NetworkConfig): string =
  let selected = getEnvOrDefault(EnvVarVersion, "latest")
  if selected == "latest":
    return fullModel.latest
  return selected

proc mapToVersion(fullModel: NetworkConfig): PrometheiNetwork =
  let selected = getVersion(fullModel)
  trace "Mapping to version", version = selected
  return PrometheiNetwork(
    spr: fullModel.sprs.filterIt(it.supportedVersions.contains(selected))[0],
    marketplace:
      fullModel.marketplace.filterIt(it.supportedVersions.contains(selected))[0],
    team: TeamObject(utils: fullModel.team.utils),
  )

proc getNetworkConfig*(): PrometheiNetwork =
  let fullModel = fetchModel()
  return mapToVersion(fullModel)
