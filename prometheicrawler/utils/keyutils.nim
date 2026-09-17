import pkg/chronicles
import pkg/questionable/results
import pkg/libp2p/crypto/crypto
import pkg/stew/io2

# This file is copied from nim-promethei `promethei/utils/keyutils.nim`

import ./rng

# from errors.nim:
template mapFailure*[T, V, E](
    exp: Result[T, V], exc: typedesc[E]
): Result[T, ref CatchableError] =
  ## Convert `Result[T, E]` to `Result[E, ref CatchableError]`
  ##

  exp.mapErr(
    proc(e: V): ref CatchableError =
      (ref exc)(msg: $e)
  )

# from fileutils.nim
when defined(windows):
  import stew/[windows/acl]

proc secureWriteFile*[T: byte | char](
    path: string, data: openArray[T]
): IoResult[void] =
  when defined(windows):
    let sres = createFilesUserOnlySecurityDescriptor()
    if sres.isErr():
      error "Could not allocate security descriptor",
        path = path, errorMsg = ioErrorMsg(sres.error), errorCode = $sres.error
      err(sres.error)
    else:
      var sd = sres.get()
      writeFile(path, data, 0o600, secDescriptor = sd.getDescriptor())
  else:
    writeFile(path, data, 0o600)

proc checkSecureFile*(path: string): IoResult[bool] =
  when defined(windows):
    checkCurrentUserOnlyACL(path)
  else:
    ok (?getPermissionsSet(path) == {UserRead, UserWrite})

type KeyError* = object of CatchableError

proc setupKey*(path: string): ?!PrivateKey =
  if not path.fileAccessible({AccessFlags.Find}):
    info "Creating a private key and saving it"
    let
      res =
        ?PrivateKey.random(PKScheme.Secp256k1, Rng.instance()[]).mapFailure(KeyError)
      bytes = ?res.getBytes().mapFailure(KeyError)

    ?path.secureWriteFile(bytes).mapFailure(KeyError)
    return PrivateKey.init(bytes).mapFailure(KeyError)

  info "Found a network private key"
  if not ?checkSecureFile(path).mapFailure(KeyError):
    warn "The network private key file is not safe, aborting"
    return failure newException(KeyError, "The network private key file is not safe")

  let kb = ?path.readAllBytes().mapFailure(KeyError)
  return PrivateKey.init(kb).mapFailure(KeyError)
