import std/os
import std/net
import std/sequtils
import pkg/chronicles
import pkg/chronos
import pkg/libp2p
import pkg/questionable
import pkg/questionable/results
import pkg/prometheidht/discv5/[routing_table, protocol as discv5]
from pkg/nimcrypto import keccak256

import ../utils/keyutils
import ../utils/datastoreutils
import ../utils/rng
import ../component
import ../state
import ../types

export discv5

logScope:
  topics = "dht"

type
  GetNeighborsResponse* = ref object
    isResponsive*: bool
    nodeIds*: seq[Nid]

  Dht* = ref object of Component
    state: State
    protocol*: discv5.Protocol
    key: PrivateKey
    peerId: PeerId
    announceAddrs*: seq[MultiAddress]
    providerRecord*: ?SignedPeerRecord
    dhtRecord*: ?SignedPeerRecord

proc responsive(nodeIds: seq[Nid]): GetNeighborsResponse =
  GetNeighborsResponse(isResponsive: true, nodeIds: nodeIds)

proc unresponsive(): GetNeighborsResponse =
  GetNeighborsResponse(isResponsive: false, nodeIds: newSeq[Nid]())

proc getNode*(d: Dht, nodeId: NodeId): ?!Node =
  let node = d.protocol.getNode(nodeId)
  if node.isSome():
    return success(node.get())
  return failure("Node not found for id: " & nodeId.toHex())

method getRoutingTableNodeIds*(d: Dht): seq[Nid] {.base, gcsafe, raises: [].} =
  var ids = newSeq[Nid]()
  for bucket in d.protocol.routingTable.buckets:
    for node in bucket.nodes:
      ids.add(node.id)
  return ids

method getNeighbors*(
    d: Dht, target: Nid
): Future[?!GetNeighborsResponse] {.async: (raises: []), base.} =
  without node =? d.getNode(target), err:
    return success(unresponsive())

  let distances = @[256.uint16]
  try:
    let response = await d.protocol.findNode(node, distances)

    if response.isOk():
      let nodes = response.get()
      return success(responsive(nodes.mapIt(it.id)))
    else:
      let errmsg = $(response.error())
      if errmsg == "Nodes message not received in time":
        return success(unresponsive())
      return failure(errmsg)
  except CatchableError as exc:
    return failure(exc.msg)

proc findPeer*(
    d: Dht, peerId: PeerId
): Future[?PeerRecord] {.async: (raises: [CancelledError]).} =
  trace "protocol.resolve..."
  try:
    let node = await d.protocol.resolve(toNodeId(peerId))
    return
      if node.isSome():
        node.get().record.data.some
      else:
        PeerRecord.none
  except CatchableError as exc:
    error "CatchableError in protocol.resolve", err = exc.msg
    return PeerRecord.none

method removeProvider*(d: Dht, peerId: PeerId): Future[void] {.base, gcsafe.} =
  trace "Removing provider", peerId
  d.protocol.removeProvidersLocal(peerId)

proc updateAnnounceRecord(d: Dht, addrs: openArray[MultiAddress]) =
  d.announceAddrs = @addrs

  trace "Updating announce record", addrs = d.announceAddrs
  d.providerRecord = SignedPeerRecord
    .init(d.key, PeerRecord.init(d.peerId, d.announceAddrs))
    .expect("Should construct signed record").some

  if not d.protocol.isNil:
    d.protocol.updateRecord(d.providerRecord).expect("Should update SPR")

proc updateDhtRecord(d: Dht, addrs: openArray[MultiAddress]) =
  trace "Updating Dht record", addrs = addrs
  d.dhtRecord = SignedPeerRecord
    .init(d.key, PeerRecord.init(d.peerId, @addrs))
    .expect("Should construct signed record").some

  if not d.protocol.isNil:
    d.protocol.updateRecord(d.dhtRecord).expect("Should update SPR")

method start*(d: Dht): Future[?!void] {.async: (raises: [CancelledError]).} =
  try:
    d.protocol.open()
    await d.protocol.start()
  except CatchableError as exc:
    return failure(exc.msg)
  return success()

method stop*(d: Dht): Future[?!void] {.async: (raises: [CancelledError]).} =
  try:
    await d.protocol.closeWait()
  except CatchableError as exc:
    return failure(exc.msg)
  return success()

proc new(
    T: type Dht,
    state: State,
    key: PrivateKey,
    bindIp = IPv4_any(),
    bindPort = 0.Port,
    announceAddrs: openArray[MultiAddress],
    bootstrapNodes: openArray[SignedPeerRecord] = [],
    store: Datastore = SQLiteDatastore.new(Memory).expect("Should not fail!"),
): Dht =
  var self = Dht(
    state: state, key: key, peerId: PeerId.init(key).expect("Should construct PeerId")
  )

  self.updateAnnounceRecord(announceAddrs)

  # This disables IP limits:
  let discoveryConfig = DiscoveryConfig(
    tableIpLimits: TableIpLimits(tableIpLimit: high(uint), bucketIpLimit: high(uint)),
    bitsPerHop: DefaultBitsPerHop,
  )

  trace "Creating DHT protocol", ip = $bindIp, port = $bindPort
  self.protocol = newProtocol(
    key,
    bindIp = bindIp,
    bindPort = bindPort,
    record = self.providerRecord.get,
    bootstrapRecords = bootstrapNodes,
    rng = Rng.instance(),
    providers = ProvidersManager.new(store),
    config = discoveryConfig,
  )

  self

proc createDht*(state: State): Future[?!Dht] {.async: (raises: [CancelledError]).} =
  without dhtStore =? createDatastore(state.config.dataDir / "dht"), err:
    return failure(err)
  let keyPath = state.config.dataDir / "privatekey"
  without privateKey =? setupKey(keyPath), err:
    return failure(err)

  var listenAddresses = newSeq[MultiAddress]()
  # TODO: when p2p connections are supported:
  # let aaa = MultiAddress.init("/ip4/" & state.config.publicIp & "/tcp/53678").expect("Should init multiaddress")
  # listenAddresses.add(aaa)

  var discAddresses = newSeq[MultiAddress]()
  let bbb = MultiAddress
    .init("/ip4/" & state.config.publicIp & "/udp/" & $state.config.discPort)
    .expect("Should init multiaddress")
  discAddresses.add(bbb)

  let dht = Dht.new(
    state,
    privateKey,
    bindPort = state.config.discPort,
    announceAddrs = listenAddresses,
    bootstrapNodes = state.config.bootNodes,
    store = dhtStore,
  )

  dht.updateAnnounceRecord(listenAddresses)
  dht.updateDhtRecord(discAddresses)

  return success(dht)
