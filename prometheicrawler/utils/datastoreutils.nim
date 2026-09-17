import pkg/chronicles
import pkg/questionable/results
import pkg/datastore
import pkg/datastore/typedds

proc createDatastore*(path: string): ?!Datastore =
  without store =? LevelDbDatastore.new(path), err:
    error "Failed to create datastore"
    return failure(err)
  return success(Datastore(store))

proc createTypedDatastore*(path: string): ?!TypedDatastore =
  without store =? createDatastore(path), err:
    return failure(err)
  return success(TypedDatastore.init(store))
