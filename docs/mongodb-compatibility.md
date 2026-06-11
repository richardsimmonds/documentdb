# MongoDB Compatibility Matrix

DocumentDB speaks the MongoDB wire protocol through its gateway (`pg_documentdb_gw`)
and executes queries against the PostgreSQL-based engine (`pg_documentdb` /
`pg_documentdb_core`). It implements a large subset of the MongoDB API surface, but
not all of it. This document is the single reference for **what is supported, what is
not, and where the gaps are.**

If you are coming from MongoDB and want to know whether your application will work,
start here.

> **How this document is maintained.** The tables below are derived directly from the
> source registries that drive the gateway and query engine — not from prose. If you
> change one of those registries, update the corresponding table here. The
> authoritative sources are called out in each section so you can verify and keep this
> document honest.

## Table of Contents

- [How to read this document](#how-to-read-this-document)
- [Database commands](#database-commands)
  - [Supported commands](#supported-commands)
  - [Recognized but not supported](#recognized-but-not-supported)
- [Query operators](#query-operators)
- [Update operators](#update-operators)
- [Aggregation pipeline stages](#aggregation-pipeline-stages)
- [Aggregation expression operators](#aggregation-expression-operators)
- [Accumulators](#accumulators)
- [Index types](#index-types)
- [Known limitations and behavioral differences](#known-limitations-and-behavioral-differences)
- [Verifying compatibility yourself](#verifying-compatibility-yourself)

---

## How to read this document

DocumentDB processes a request in two layers:

1. **The gateway** (`pg_documentdb_gw`, Rust) terminates the MongoDB wire protocol,
   parses the command, and dispatches it. A command can be *recognized* (the gateway
   knows the command name) but still *not supported* (there is no handler, so it
   returns `CommandNotSupported`).
2. **The query engine** (`pg_documentdb`, C as a PostgreSQL extension) implements the
   query operators, update operators, aggregation stages, and expression operators.

"Supported" in this document means there is a real handler in the current source tree
— not merely that the name is parsed. Each table names the file it was generated from
so you can confirm.

A few conventions:

- ✅ **Supported** — there is an implemented handler.
- ⚠️ **Partial / conditional** — supported, but gated behind a feature flag, limited in
  scope, or with known behavioral differences. See notes.
- ❌ **Not supported** — recognized by the protocol but returns an error, or not
  implemented at all.

---

## Database commands

The gateway recognizes the full MongoDB command vocabulary (so that unsupported
commands fail with a clear error rather than a generic parse failure), but only a
subset is dispatched to a handler.

**Source of truth:**
`pg_documentdb_gw/documentdb_gateway_core/src/processor/process.rs` (dispatch `match`)
and `.../src/requests/request_type.rs` (the recognized-command enum).

### Supported commands

These commands have a handler in `process_request`.

| Command | Category | Notes |
|---|---|---|
| `aggregate` | CRUD / query | Full aggregation pipeline. See [stages](#aggregation-pipeline-stages). |
| `count` | CRUD / query | |
| `distinct` | CRUD / query | |
| `find` | CRUD / query | |
| `findAndModify` | CRUD / write | |
| `getMore` | Cursor | Cursor continuation. |
| `insert` | CRUD / write | Honors `enableWriteProcedures` GUCs for batching. |
| `update` | CRUD / write | Honors `enableWriteProcedures` GUCs for batching. |
| `delete` | CRUD / write | |
| `killCursors` | Cursor | |
| `explain` | Diagnostics | Supports `find` and `aggregate` plans. |
| `validate` | Diagnostics | |
| `create` | DDL | Create collection / view. |
| `drop` | DDL | Drop collection. |
| `dropDatabase` | DDL | |
| `createIndex` / `createIndexes` | Index | See [index types](#index-types). |
| `listIndexes` | Index | |
| `dropIndexes` | Index | |
| `reIndex` | Index | |
| `collMod` | DDL | |
| `renameCollection` | DDL | |
| `listCollections` | Metadata | |
| `listDatabases` | Metadata | |
| `collStats` | Stats | |
| `dbStats` | Stats | |
| `compact` | Maintenance | |
| `getParameter` | Admin | |
| `currentOp` | Admin | |
| `killOp` | Admin | |
| `connectionStatus` | Admin | Gated on `enableConnectionStatus`; falls back to a constant response otherwise. |
| `ping` | Admin | |
| `hello` / `isMaster` / `ismaster` | Handshake | Reports `isWritablePrimary`. |
| `buildInfo` | Handshake | |
| `hostInfo` | Handshake | |
| `getCmdLineOpts` | Admin | |
| `getLog` | Admin | |
| `getDefaultRWConcern` | Admin | |
| `whatsMyUri` | Admin | |
| `isdbgrid` | Sharding | |
| `listCommands` | Admin | |
| `prepareTransaction` | Transactions | |
| `commitTransaction` | Transactions | |
| `abortTransaction` | Transactions | |
| `endSessions` / `killSessions` | Sessions | |
| `createUser` / `dropUser` / `updateUser` / `usersInfo` | Auth / users | |
| `createRole` / `updateRole` / `dropRole` / `rolesInfo` | Auth / RBAC | |
| `shardCollection` | Sharding | |
| `reshardCollection` | Sharding | Routed through the shard-collection handler. |
| `unshardCollection` | Sharding | |
| `getShardMap` | Sharding | |
| `listShards` | Sharding | |
| `balancerStart` / `balancerStatus` / `balancerStop` | Sharding | |
| `moveCollection` | Sharding | |
| `saslStart` / `saslContinue` / `logout` | Auth | Handled in the auth layer before dispatch. |

### Recognized but not supported

The command enum in `request_type.rs` contains the **complete** MongoDB command
vocabulary so that unknown-but-valid commands return a precise error. Any command name
in that enum that does **not** appear in the supported table above is dispatched to the
catch-all arm and returns:

```
CommandNotSupported: Command '<name>' not supported.
```

This includes (non-exhaustive) replica-set internals (`replSet*`), config-server
internals (`_configsvr*`, `_shardsvr*`), chunk-migration internals (`_recvChunk*`,
`_migrateClone`, `moveChunk`, `mergeChunks`, `splitChunk`, `splitVector`),
`mapReduce`, `group`, `eval`, `geoSearch`, `parallelCollectionScan`,
`setParameter`, `setFeatureCompatibilityVersion`, `serverStatus`, `fsync`,
`profile`, `planCache*`, free-monitoring commands, and the legacy
`getLastError` / `getPrevError` / `resetError` family.

> **Rule of thumb:** if it is a sharded-cluster control-plane command, a replica-set
> management command, or a deprecated MongoDB command, assume it is not supported and
> verify against `process.rs`.

---

## Query operators

These are the operators usable in query filters (`find`, the `$match` stage, the
`query` field of `update` / `delete` / `findAndModify`).

**Source of truth:**
`pg_documentdb/include/planner/mongo_query_operator.h` (`MongoQueryOperatorType` enum).

| Category | Operators | Status |
|---|---|---|
| Comparison | `$eq`, `$gt`, `$gte`, `$lt`, `$lte`, `$ne`, `$in`, `$nin` | ✅ |
| Array | `$all`, `$elemMatch`, `$size` | ✅ |
| Logical | `$and`, `$or`, `$not`, `$nor` | ✅ |
| Element | `$exists`, `$type` | ✅ |
| Evaluation | `$regex`, `$mod`, `$text`, `$expr`, `$jsonSchema`, `$sampleRate` | ✅ |
| Bitwise | `$bitsAllClear`, `$bitsAnyClear`, `$bitsAllSet`, `$bitsAnySet` | ✅ |
| Geospatial | `$geoWithin`, `$geoIntersects`, `$near`, `$nearSphere`, `$geoNear`, `$within` (legacy) | ✅ See the [Search Guide](search-guide.md). |
| Misc | `$comment` | ✅ |

> `$where` (server-side JavaScript predicates) is **not** in the operator table and is
> not supported.

---

## Update operators

Usable in the `update` document of `update` and `findAndModify`.

**Source of truth:**
`pg_documentdb/src/update/bson_update_operators_workflow.c` (`MongoUpdateOperators[]`).

| Category | Operators | Status |
|---|---|---|
| Field | `$set`, `$unset`, `$inc`, `$mul`, `$min`, `$max`, `$rename`, `$setOnInsert`, `$currentDate` | ✅ |
| Array | `$push`, `$pop`, `$pull`, `$pullAll`, `$addToSet` | ✅ |
| Bitwise | `$bit` | ✅ |

Array update modifiers (`$each`, `$position`, `$slice`, `$sort` inside `$push`, and the
positional operators `$` / `$[]` / `$[<identifier>]`) are handled within the operators
above; coverage follows MongoDB semantics. Validate edge cases against the regression
tests in `pg_documentdb/src/test/regress/` if you depend on subtle behavior.

---

## Aggregation pipeline stages

**Source of truth:**
`pg_documentdb/src/aggregation/bson_aggregation_pipeline.c` (`StageDefinitions[]`).
Every entry below has an implemented `mutateFunc`.

| Stage | Status | Notes |
|---|---|---|
| `$addFields` / `$set` | ✅ | |
| `$bucket` | ✅ | |
| `$bucketAuto` | ✅ | |
| `$changeStream` | ✅ | |
| `$collStats` | ✅ | |
| `$count` | ✅ | |
| `$currentOp` | ✅ | |
| `$densify` | ✅ | |
| `$documents` | ✅ | |
| `$facet` | ✅ | |
| `$fill` | ✅ | |
| `$geoNear` | ✅ | See the [Search Guide](search-guide.md). |
| `$graphLookup` | ✅ | |
| `$group` | ✅ | |
| `$indexStats` | ✅ | |
| `$inverseMatch` | ✅ | DocumentDB extension. |
| `$limit` | ✅ | |
| `$listLocalSessions` | ✅ | |
| `$listSessions` | ✅ | |
| `$lookup` | ✅ | |
| `$match` | ✅ | |
| `$merge` | ✅ | Output stage. |
| `$out` | ✅ | Output stage. |
| `$project` | ✅ | |
| `$redact` | ✅ | |
| `$replaceRoot` / `$replaceWith` | ✅ | |
| `$sample` | ✅ | |
| `$search` | ✅ | Vector search. See the [Search Guide](search-guide.md). |
| `$searchMeta` | ✅ | |
| `$set` | ✅ | Alias of `$addFields`. |
| `$setWindowFields` | ✅ | |
| `$skip` | ✅ | |
| `$sort` | ✅ | |
| `$sortByCount` | ✅ | |
| `$unionWith` | ✅ | |
| `$unset` | ✅ | |
| `$unwind` | ✅ | |
| `$vectorSearch` | ✅ | See the [Search Guide](search-guide.md). |

DocumentDB also defines internal optimization stages (`$_internalInhibitOptimization`,
`$lookupUnwind`, `$sortGroup`) that the planner uses internally; they are not part of
the public API.

> Stages **not** listed above (for example `$planCacheStats`,
> `$listClusterCatalog`, `$shardedDataDistribution`) are not implemented and will be
> rejected.

---

## Aggregation expression operators

Usable inside `$project`, `$group`, `$addFields`, `$match` (`$expr`), and similar.

**Source of truth:** `pg_documentdb/src/operators/bson_expression.c`
(`OperatorExpressions[]`). All entries are listed; a handful are parse-only stubs (no
runtime handler yet) and are flagged ⚠️.

| Category | Operators |
|---|---|
| Arithmetic | `$abs`, `$add`, `$ceil`, `$divide`, `$exp`, `$floor`, `$ln`, `$log`, `$log10`, `$mod`, `$multiply`, `$pow`, `$round`, `$sqrt`, `$subtract`, `$trunc` |
| Trigonometry | `$acos`, `$acosh`, `$asin`, `$asinh`, `$atan`, `$atan2`, `$atanh`, `$cos`, `$cosh`, `$degreesToRadians`, `$radiansToDegrees`, `$sin`, `$sinh`, `$tan`, `$tanh` |
| Array | `$arrayElemAt`, `$arrayToObject`, `$concatArrays`, `$filter`, `$first`, `$firstN`, `$in`, `$indexOfArray`, `$isArray`, `$last`, `$lastN`, `$map`, `$maxN`, `$minN`, `$objectToArray`, `$range`, `$reduce`, `$reverseArray`, `$size`, `$slice`, `$sortArray`, `$zip`, `$makeArray` |
| Boolean / comparison | `$and`, `$or`, `$not`, `$allElementsTrue`, `$anyElementTrue`, `$cmp`, `$eq`, `$gt`, `$gte`, `$lt`, `$lte`, `$ne` |
| Conditional | `$cond`, `$ifNull`, `$switch` |
| String | `$concat`, `$indexOfBytes`, `$indexOfCP`, `$ltrim`, `$replaceAll`, `$replaceOne`, `$rtrim`, `$split`, `$strcasecmp`, `$strLenBytes`, `$strLenCP`, `$substr`, `$substrBytes`, `$substrCP`, `$toLower`, `$toUpper`, `$trim` |
| Regex | `$regexFind`, `$regexFindAll`, `$regexMatch` |
| Date | `$dateAdd`, `$dateDiff`, `$dateFromParts`, `$dateFromString`, `$dateSubtract`, `$dateToParts`, `$dateToString`, `$dateTrunc`, `$dayOfMonth`, `$dayOfWeek`, `$dayOfYear`, `$hour`, `$isoDayOfWeek`, `$isoWeek`, `$isoWeekYear`, `$millisecond`, `$minute`, `$month`, `$second`, `$week`, `$year` |
| Type conversion | `$convert`, `$toBool`, `$toDate`, `$toDecimal`, `$toDouble`, `$toInt`, `$toLong`, `$toObjectId`, `$toString`, `$toUUID`, `$type`, `$isNumber` |
| Object / field | `$getField`, `$setField`, `$unsetField`, `$mergeObjects` |
| Set | `$setDifference`, `$setEquals`, `$setIntersection`, `$setIsSubset`, `$setUnion` |
| Bitwise | `$bitAnd`, `$bitNot`, `$bitOr`, `$bitXor` |
| Variable / literal | `$let`, `$literal`, `$const` |
| Misc | `$binarySize`, `$bsonSize`, `$meta`, `$rand`, `$toHashedIndexKey`, `$tsIncrement`, `$tsSecond` |
| ⚠️ Parse-only (no runtime handler in this tree) | `$accumulator`, `$function` |

> `$accumulator` and `$function` (server-side JavaScript) are present in the registry
> but have `NULL` parse/handle functions — treat them as **not supported**.

---

## Accumulators

Used in `$group`, `$bucket`, `$bucketAuto`, and `$setWindowFields`.

**Source of truth:** `OperatorExpressions[]` in `bson_expression.c` (accumulators share
the expression registry).

| Accumulator | Status |
|---|---|
| `$sum` | ✅ |
| `$avg` | ✅ |
| `$min` | ✅ |
| `$max` | ✅ |
| `$first` | ✅ |
| `$last` | ✅ |
| `$firstN` / `$lastN` / `$minN` / `$maxN` | ✅ |
| `$push` | ✅ |
| `$addToSet` | ✅ |
| `$mergeObjects` | ✅ |
| `$stdDevPop` / `$stdDevSamp` | ⚠️ Registered, but parse/handle functions are `NULL` in this tree — verify before relying on them. |

---

## Index types

Index types accepted by `createIndex` / `createIndexes`.

**Source of truth:** `pg_documentdb/src/metadata/index.c`
(`MongoIndexSupportedList[]`).

| Type | Status | Notes |
|---|---|---|
| Single-field / compound (ascending/descending) | ✅ | The default; specify `{ field: 1 }` / `{ field: -1 }`. |
| `2d` | ✅ | Legacy flat geospatial. See the [Search Guide](search-guide.md). |
| `2dsphere` | ✅ | Spherical geospatial. |
| `text` | ✅ | Full-text (backed by RUM). See the [Search Guide](search-guide.md). |
| `hashed` | ✅ | |
| `cosmosSearch` | ✅ | Vector index (HNSW / IVF). See the [Search Guide](search-guide.md). |

Index options such as `unique`, `sparse`, `partialFilterExpression`, TTL
(`expireAfterSeconds`), and wildcard key patterns (`{ "$**": 1 }`) are supported on the
applicable index types. Validate specific combinations against the index regression
tests if you depend on a particular option.

---

## Known limitations and behavioral differences

- **No server-side JavaScript.** `$where`, `mapReduce`, `eval`, the `$function`
  expression, and the `$accumulator` custom accumulator are not supported.
- **No replica-set or config-server control plane.** DocumentDB presents itself as a
  writable primary (`hello` / `isMaster`), but `replSet*`, `_configsvr*`, and
  `_shardsvr*` commands are not implemented. Replication and HA are handled at the
  PostgreSQL layer, not through MongoDB replica-set commands.
- **Sharding is partial.** `shardCollection`, `reshardCollection`, `unshardCollection`,
  the balancer commands, and shard-map inspection are supported, but the low-level
  chunk-migration commands (`moveChunk`, `mergeChunks`, `splitChunk`, `splitVector`,
  and the `_recvChunk*` internals) are not.
- **Some diagnostics commands are absent.** `serverStatus`, `setParameter`,
  `setFeatureCompatibilityVersion`, `profile`, and the `planCache*` family are not
  supported. Use `getParameter`, `collStats`, `dbStats`, and `currentOp` for the
  diagnostics that are available, and fall back to PostgreSQL's own tooling for the
  rest.
- **Feature-flag gating.** Some behavior is controlled by GUCs (PostgreSQL
  configuration parameters), e.g. write-procedure batching (`enableWriteProcedures*`)
  and `enableConnectionStatus`. A command can be supported but behave differently
  depending on configuration. See the GUC / feature-flag reference for details.
- **Stubs are not support.** A few operators (`$accumulator`, `$function`,
  `$stdDevPop`, `$stdDevSamp`) appear in the registries with `NULL` handlers. They are
  recognized but will not execute; treat them as unsupported until a handler lands.

---

## Verifying compatibility yourself

This document is generated from source. To confirm any entry against the code you are
running:

```bash
# Which commands does the gateway dispatch?
grep -n 'RequestType::' pg_documentdb_gw/documentdb_gateway_core/src/processor/process.rs

# The full recognized-command vocabulary
grep -n '=> "' pg_documentdb_gw/documentdb_gateway_core/src/requests/request_type.rs

# Query operators
sed -n '/MongoQueryOperatorType/,/MongoQueryOperatorType;/p' \
  pg_documentdb/include/planner/mongo_query_operator.h

# Update operators
grep -n '.operatorName' pg_documentdb/src/update/bson_update_operators_workflow.c

# Aggregation stages
grep -n '.stage = "' pg_documentdb/src/aggregation/bson_aggregation_pipeline.c

# Aggregation expression operators
sed -n '/OperatorExpressions\[\] = {/,/^};/p' pg_documentdb/src/operators/bson_expression.c

# Index types
sed -n '/MongoIndexSupportedList\[\]/,/};/p' pg_documentdb/src/metadata/index.c
```

You can also query a running server: `db.runCommand({ listCommands: 1 })` returns the
commands the gateway advertises.

If you find a discrepancy between this document and the source, the source wins —
please open a PR fixing the table.
