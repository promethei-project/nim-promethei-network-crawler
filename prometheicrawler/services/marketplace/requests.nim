import std/hashes
import std/sequtils
import std/typetraits
import pkg/contractabi
import pkg/nimcrypto
import pkg/ethers/contracts/fields
import pkg/results
import pkg/questionable/results
import pkg/stew/byteutils
import pkg/libp2p/[cid, multicodec]
import pkg/serde/json
import ./logutils

export contractabi

type
  TokensPerSecond* = object
    value: StUint[96]

  Tokens* = object
    value: StUint[128]

  StorageTimestamp* = object
    value: StUint[40]

  StorageDuration* = object
    value: StUint[40]

  ProofPeriod* = object
    value: StUint[40]

  StorageRequest* = object
    client* {.serialize.}: Address
    ask* {.serialize.}: StorageAsk
    content* {.serialize.}: StorageContent
    expiry* {.serialize.}: StorageDuration
    nonce*: Nonce

  StorageAsk* = object
    proofProbability* {.serialize.}: UInt256
    pricePerBytePerSecond* {.serialize.}: TokensPerSecond
    collateralPerByte* {.serialize.}: Tokens
    slots* {.serialize.}: uint64
    slotSize* {.serialize.}: uint64
    duration* {.serialize.}: StorageDuration
    maxSlotLoss* {.serialize.}: uint64

  StorageContent* = object
    cid* {.serialize.}: Cid
    merkleRoot*: array[32, byte]

  Slot* = object
    request* {.serialize.}: StorageRequest
    slotIndex* {.serialize.}: uint64

  SlotId* = distinct array[32, byte]
  RequestId* = distinct array[32, byte]
  Nonce* = distinct array[32, byte]
  RequestState* {.pure.} = enum
    New
    Started
    Cancelled
    Finished
    Failed

  SlotState* {.pure.} = enum
    Free
    Filled
    Finished
    Failed
    Cancelled
    Repair

template mapFailure*[T, V, E](
    exp: Result[T, V], exc: typedesc[E]
): Result[T, ref CatchableError] =
  ## Convert `Result[T, E]` to `Result[E, ref CatchableError]`
  ##

  exp.mapErr(
    proc(e: V): ref CatchableError =
      (ref exc)(msg: $e)
  )

template mapFailure*[T, V](exp: Result[T, V]): Result[T, ref CatchableError] =
  mapFailure(exp, CatchableError)

proc `==`*(x, y: Nonce): bool {.borrow.}
proc `==`*(x, y: RequestId): bool {.borrow.}
proc `==`*(x, y: SlotId): bool {.borrow.}
proc hash*(x: SlotId): Hash {.borrow.}
proc hash*(x: Nonce): Hash {.borrow.}
proc hash*(x: Address): Hash {.borrow.}

func toArray*(id: RequestId | SlotId | Nonce): array[32, byte] =
  array[32, byte](id)

proc `$`*(id: RequestId | SlotId | Nonce): string =
  id.toArray.toHex

proc fromHex*(T: type RequestId, hex: string): T =
  T array[32, byte].fromHex(hex)

proc fromHex*(T: type SlotId, hex: string): T =
  T array[32, byte].fromHex(hex)

proc fromHex*(T: type Nonce, hex: string): T =
  T array[32, byte].fromHex(hex)

proc fromHex*[T: distinct](_: type T, hex: string): T =
  type baseType = T.distinctBase
  T baseType.fromHex(hex)

proc toHex*[T: distinct](id: T): string =
  type baseType = T.distinctBase
  baseType(id).toHex

logutils.formatIt(LogFormat.textLines, Nonce):
  it.short0xHexLog
logutils.formatIt(LogFormat.textLines, RequestId):
  it.short0xHexLog
logutils.formatIt(LogFormat.textLines, SlotId):
  it.short0xHexLog
logutils.formatIt(LogFormat.json, Nonce):
  it.to0xHexLog
logutils.formatIt(LogFormat.json, RequestId):
  it.to0xHexLog
logutils.formatIt(LogFormat.json, SlotId):
  it.to0xHexLog

func fromTuple(_: type StorageRequest, tupl: tuple): StorageRequest =
  StorageRequest(
    client: tupl[0], ask: tupl[1], content: tupl[2], expiry: tupl[3], nonce: tupl[4]
  )

func fromTuple(_: type Slot, tupl: tuple): Slot =
  Slot(request: tupl[0], slotIndex: tupl[1])

func fromTuple(_: type StorageAsk, tupl: tuple): StorageAsk =
  StorageAsk(
    proofProbability: tupl[0],
    pricePerBytePerSecond: tupl[1],
    collateralPerByte: tupl[2],
    slots: tupl[3],
    slotSize: tupl[4],
    duration: tupl[5],
    maxSlotLoss: tupl[6],
  )

func fromTuple(_: type StorageContent, tupl: tuple): StorageContent =
  StorageContent(cid: tupl[0], merkleRoot: tupl[1])

func u40*(duration: StorageDuration): StUint[40] =
  duration.value

func u40*(duration: StorageTimestamp): StUint[40] =
  duration.value

func u40*(period: ProofPeriod): StUint[40] =
  period.value

func u64*(duration: StorageDuration): uint64 =
  duration.value.truncate(uint64)

func u64*(timestamp: StorageTimestamp): uint64 =
  timestamp.value.truncate(uint64)

func u64*(period: ProofPeriod): uint64 =
  period.value.truncate(uint64)

func u256*(timestamp: StorageTimestamp): UInt256 =
  timestamp.value.stuint(256)

func u256*(duration: StorageDuration): UInt256 =
  duration.value.stuint(256)

func `'StorageDuration`*(value: static string): StorageDuration =
  const parsed = parse(value, StUint[40])
  StorageDuration(value: parsed)

func `'StorageTimestamp`*(value: static string): StorageTimestamp =
  const parsed = parse(value, StUint[40])
  StorageTimestamp(value: parsed)

func `'ProofPeriod`*(value: static string): ProofPeriod =
  const parsed = parse(value, StUint[40])
  ProofPeriod(value: parsed)

func init*(_: type StorageDuration, value: StUint[40]): StorageDuration =
  StorageDuration(value: value)

func init*(_: type StorageDuration, value: uint32 | uint16 | uint8): StorageDuration =
  StorageDuration.init(value.stuint(40))

func init*(_: type StorageTimestamp, value: StUint[40]): StorageTimestamp =
  StorageTimestamp(value: value)

func init*(_: type StorageTimestamp, value: uint32 | uint16 | uint8): StorageTimestamp =
  StorageTimestamp.init(value.stuint(40))

func init*(_: type ProofPeriod, value: StUint[40]): ProofPeriod =
  ProofPeriod(value: value)

func `*`*(a: StorageDuration, b: uint32 | uint16 | uint8): StorageDuration =
  StorageDuration.init(a.value * b.stuint(40))

func `+`*(a: StorageTimestamp, b: StorageDuration): StorageTimestamp =
  StorageTimestamp(value: a.value + b.value)

func `+`*(a: StorageTimestamp, b: uint32 | uint16 | uint8): StorageTimestamp =
  StorageTimestamp(value: a.value + b.stuint(40))

func `+`*(a: StorageDuration, b: StorageDuration): StorageDuration =
  StorageDuration(value: a.value + b.value)

func `+`*(a: StorageDuration, b: uint32 | uint16 | uint8): StorageDuration =
  StorageDuration(value: a.value + b.stuint(40))

func `+`*(a: ProofPeriod, b: uint32 | uint16 | uint8): ProofPeriod =
  ProofPeriod(value: a.value + b.stuint(40))

func `-`*(a: StorageTimestamp, b: uint32 | uint16 | uint8): StorageTimestamp =
  StorageTimestamp(value: a.value - b.stuint(40))

func `-`*(a: StorageDuration, b: StorageDuration): StorageDuration =
  StorageDuration(value: a.value - b.value)

func `-`*(a: StorageDuration, b: uint32 | uint16 | uint8): StorageDuration =
  StorageDuration(value: a.value - b.stuint(40))

func `-`*(a: ProofPeriod, b: uint32 | uint16 | uint8): ProofPeriod =
  ProofPeriod(value: a.value - b.stuint(40))

func `+=`*(a: var StorageTimestamp, b: StorageDuration): StorageTimestamp =
  a.value += b.value

func `+=`*[T: StorageDuration | StorageTimestamp](a: var T, b: T) =
  a.value += b.value

func `-=`*[T: StorageDuration | StorageTimestamp](a: var T, b: T) =
  a.value -= b.value

func `<`*(a, b: StorageDuration | StorageTimestamp | ProofPeriod): bool =
  a.value < b.value

func `>`*(a, b: StorageDuration | StorageTimestamp): bool =
  a.value > b.value

func `<=`*(a, b: StorageDuration | StorageTimestamp): bool =
  a.value <= b.value

func `>=`*(a, b: StorageDuration | StorageTimestamp): bool =
  a.value >= b.value

func until*(earlier, later: StorageTimestamp): StorageDuration =
  doAssert earlier <= later
  StorageDuration.init(later.u40 - earlier.u40)

func solidityType*(_: type StorageDuration): string =
  "uint40"

func solidityType*(_: type StorageTimestamp): string =
  "uint40"

func solidityType*(_: type ProofPeriod): string =
  "uint40"

func encode*(encoder: var AbiEncoder, timestamp: StorageDuration) =
  encoder.write(timestamp.value)

func encode*(encoder: var AbiEncoder, timestamp: StorageTimestamp) =
  encoder.write(timestamp.value)

func encode*(encoder: var AbiEncoder, period: ProofPeriod) =
  encoder.write(period.value)

func decode*(decoder: var AbiDecoder, T: type StorageDuration): ?!T =
  let value = ?decoder.read(T.value)
  success T(value: value)

func decode*(decoder: var AbiDecoder, T: type StorageTimestamp): ?!T =
  let value = ?decoder.read(T.value)
  success T(value: value)

func decode*(decoder: var AbiDecoder, T: type ProofPeriod): ?!T =
  let value = ?decoder.read(T.value)
  success T(value: value)

func `%`*(value: StorageDuration | StorageTimestamp | ProofPeriod): JsonNode =
  %($value.value)

func fromJson*(_: type StorageDuration, json: JsonNode): ?!StorageDuration =
  success StorageDuration(value: ?StUint[40].fromJson(json))

func fromJson*(_: type StorageTimestamp, json: JsonNode): ?!StorageTimestamp =
  success StorageTimestamp(value: ?StUint[40].fromJson(json))

func fromJson*(_: type ProofPeriod, json: JsonNode): ?!ProofPeriod =
  success ProofPeriod(value: ?StUint[40].fromJson(json))

func u256*(tokensPerSecond: TokensPerSecond): UInt256 =
  tokensPerSecond.value.stuint(256)

func u256*(tokens: Tokens): UInt256 =
  tokens.value.stuint(256)

func `'TokensPerSecond`*(value: static string): TokensPerSecond =
  const parsed = parse(value, StUint[96])
  TokensPerSecond(value: parsed)

func `'Tokens`*(value: static string): Tokens =
  const parsed = parse(value, UInt128)
  Tokens(value: parsed)

func init*(_: type TokensPerSecond, value: StUint[96]): TokensPerSecond =
  TokensPerSecond(value: value)

func init*(_: type TokensPerSecond, value: SomeUnsignedInt): TokensPerSecond =
  TokensPerSecond.init(value.stuint(96))

func init*(_: type Tokens, value: UInt128): Tokens =
  Tokens(value: value)

func init*(_: type Tokens, value: SomeUnsignedInt): Tokens =
  Tokens.init(value.stuint(128))

func `*`*(a: TokensPerSecond, b: SomeUnsignedInt): TokensPerSecond =
  TokensPerSecond(value: a.value * b.stuint(96))

func `*`*(a: TokensPerSecond, b: StorageDuration): Tokens =
  Tokens(value: a.value.stuint(128) * b.u40.stuint(128))

func `*`*(a: Tokens, b: SomeUnsignedInt): Tokens =
  Tokens(value: a.value * b.stuint(128))

func `div`*(a: Tokens, b: SomeUnsignedInt): Tokens =
  Tokens(value: a.value div b.stuint(128))

func `+`*(a, b: Tokens): Tokens =
  Tokens(value: a.value + b.value)

func `+`*(a: Tokens, b: SomeUnsignedInt): Tokens =
  Tokens(value: a.value + b.u128)

func `+`*(a, b: TokensPerSecond): TokensPerSecond =
  TokensPerSecond(value: a.value + b.value)

func `+`*(a: TokensPerSecond, b: SomeUnsignedInt): TokensPerSecond =
  TokensPerSecond(value: a.value + b.stuint(96))

func `-`*(a, b: Tokens): Tokens =
  Tokens(value: a.value - b.value)

func `+=`*[T: Tokens | TokensPerSecond](a: var T, b: T) =
  a.value += b.value

func `-=`*[T: Tokens | TokensPerSecond](a: var T, b: T) =
  a.value -= b.value

func `<`*(a, b: Tokens | TokensPerSecond): bool =
  a.value < b.value

func `>`*(a, b: Tokens | TokensPerSecond): bool =
  a.value > b.value

func `<=`*(a, b: Tokens | TokensPerSecond): bool =
  a.value <= b.value

func `>=`*(a, b: Tokens | TokensPerSecond): bool =
  a.value >= b.value

func solidityType*(_: type TokensPerSecond): string =
  "uint96"

func solidityType*(_: type Tokens): string =
  "uint128"

func encode*(encoder: var AbiEncoder, tokensPerSecond: TokensPerSecond) =
  encoder.write(tokensPerSecond.value)

func encode*(encoder: var AbiEncoder, tokens: Tokens) =
  encoder.write(tokens.value)

func decode*(decoder: var AbiDecoder, T: type TokensPerSecond): ?!T =
  let value = ?decoder.read(T.value)
  success T(value: value)

func decode*(decoder: var AbiDecoder, T: type Tokens): ?!T =
  let value = ?decoder.read(T.value)
  success T(value: value)

func `%`*(value: TokensPerSecond | Tokens): JsonNode =
  %($value.value)

func fromJson*(_: type TokensPerSecond, json: JsonNode): ?!TokensPerSecond =
  success TokensPerSecond(value: ?StUint[96].fromJson(json))

func fromJson*(_: type Tokens, json: JsonNode): ?!Tokens =
  success Tokens(value: ?UInt128.fromJson(json))

func solidityType*(_: type StUint[40]): string =
  "uint40"

func solidityType*(_: type StUint[96]): string =
  "uint96"

func solidityType*(_: type Cid): string =
  solidityType(seq[byte])

func solidityType*(_: type StorageContent): string =
  solidityType(StorageContent.fieldTypes)

func solidityType*(_: type StorageAsk): string =
  solidityType(StorageAsk.fieldTypes)

func solidityType*(_: type StorageRequest): string =
  solidityType(StorageRequest.fieldTypes)

# Note: it seems to be ok to ignore the vbuffer offset for now
func encode*(encoder: var AbiEncoder, cid: Cid) =
  encoder.write(cid.data.buffer)

func encode*(encoder: var AbiEncoder, content: StorageContent) =
  encoder.write(content.fieldValues)

func encode*(encoder: var AbiEncoder, ask: StorageAsk) =
  encoder.write(ask.fieldValues)

func encode*(encoder: var AbiEncoder, id: RequestId | SlotId | Nonce) =
  encoder.write(id.toArray)

func encode*(encoder: var AbiEncoder, request: StorageRequest) =
  encoder.write(request.fieldValues)

func encode*(encoder: var AbiEncoder, slot: Slot) =
  encoder.write(slot.fieldValues)

func decode*(decoder: var AbiDecoder, T: type Cid): ?!T =
  let data = ?decoder.read(seq[byte])
  Cid.init(data).mapFailure

func decode*(decoder: var AbiDecoder, T: type StorageContent): ?!T =
  let tupl = ?decoder.read(StorageContent.fieldTypes)
  success StorageContent.fromTuple(tupl)

func decode*(decoder: var AbiDecoder, T: type StorageAsk): ?!T =
  let tupl = ?decoder.read(StorageAsk.fieldTypes)
  success StorageAsk.fromTuple(tupl)

func decode*(decoder: var AbiDecoder, T: type StorageRequest): ?!T =
  let tupl = ?decoder.read(StorageRequest.fieldTypes)
  success StorageRequest.fromTuple(tupl)

func decode*(decoder: var AbiDecoder, T: type Slot): ?!T =
  let tupl = ?decoder.read(Slot.fieldTypes)
  success Slot.fromTuple(tupl)

func id*(request: StorageRequest): RequestId =
  let encoding = AbiEncoder.encode((request,))
  RequestId(keccak256.digest(encoding).data)

func slotId*(requestId: RequestId, slotIndex: uint64): SlotId =
  let encoding = AbiEncoder.encode((requestId, slotIndex))
  SlotId(keccak256.digest(encoding).data)

func slotId*(request: StorageRequest, slotIndex: uint64): SlotId =
  slotId(request.id, slotIndex)

func id*(slot: Slot): SlotId =
  slotId(slot.request, slot.slotIndex)

func pricePerSlotPerSecond*(ask: StorageAsk): TokensPerSecond =
  ask.pricePerBytePerSecond * ask.slotSize

func pricePerSlot*(ask: StorageAsk): Tokens =
  ask.pricePerSlotPerSecond * ask.duration

func totalPrice*(ask: StorageAsk): Tokens =
  ask.pricePerSlot * ask.slots

func totalPrice*(request: StorageRequest): Tokens =
  request.ask.totalPrice

func collateralPerSlot*(ask: StorageAsk): Tokens =
  ask.collateralPerByte * ask.slotSize

func size*(ask: StorageAsk): uint64 =
  ask.slots * ask.slotSize
