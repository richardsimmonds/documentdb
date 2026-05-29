# DocumentDB Configuration Reference

DocumentDB exposes its settings as PostgreSQL Grand Unified Configuration (GUC)
parameters. All parameters live under the `documentdb.` prefix and can be set in
`postgresql.conf`, with `SET` / `ALTER SYSTEM SET`, or passed as connection
options.

> **Scope key**
>
> | Abbreviation | PostgreSQL context | When it takes effect |
> |---|---|---|
> | `USERSET` | `PGC_USERSET` | Any session, any time |
> | `SUSET` | `PGC_SUSET` | Superuser only, any time |
> | `POSTMASTER` | `PGC_POSTMASTER` | Server start only |

---

## Feature Flags

Feature flags are boolean GUCs that gate in-progress or recently-shipped
behaviors. They default to `false` while a feature is stabilizing and `true`
once it has been promoted. Flags marked **Pending stabilization** are still
being validated; do not rely on them in production without testing.

All feature-flag parameters are `USERSET` scope unless noted.

### Authentication & Authorization

| GUC name | Default | Description |
|---|---|---|
| `documentdb.enableUsernamePasswordConstraints` | `on` | Enforce username and password constraints (minimum length, disallowed characters). |
| `documentdb.enableUsersInfoPrivileges` | `on` | Include privilege information in `usersInfo` command responses. |
| `documentdb.isNativeAuthEnabled` | `on` | Enable native SCRAM-SHA-256 authentication. |
| `documentdb.enableRoleCrud` | `off` | Enable role create/read/update/delete through the data plane. Pending stabilization. |
| `documentdb.enableUsersAdminDBCheck` | `off` | Require the `admin` database context for user CRUD APIs. Pending stabilization. |
| `documentdb.enableRolesAdminDBCheck` | `on` | Require the `admin` database context for role CRUD APIs. |

### Schema Validation

| GUC name | Default | Description |
|---|---|---|
| `documentdb.enableSchemaValidation` | `off` | Support `$jsonSchema` validator rules on collections. Pending stabilization. |
| `documentdb.enableBypassDocumentValidation` | `off` | Honor the `bypassDocumentValidation` flag in write commands. Pending stabilization. |

### Vector Search

| GUC name | Default | Description |
|---|---|---|
| `documentdb.enableVectorHNSWIndex` | `on` | Enable HNSW index type and query for vector search. |
| `documentdb.enableVectorPreFilter` | `on` | Enable pre-filtering for vector search queries. |
| `documentdb.enableVectorPreFilterV2` | `off` | Enable pre-filtering v2 (revised algorithm). Pending stabilization. |
| `documentdb.enable_force_push_vector_index` | `off` | Always push vector queries to the vector index regardless of planner cost. |
| `documentdb.enableVectorCompressionHalf` | `on` | Enable half-precision compression for vector indexes. |
| `documentdb.enableVectorCompressionPQ` | `on` | Enable product quantization (PQ) compression for vector indexes. |
| `documentdb.enableVectorCalculateDefaultSearchParam` | `on` | Automatically calculate a default `ef_search` / `probes` value for vector queries. |

### Indexing

| GUC name | Default | Description |
|---|---|---|
| `documentdb.defaultUseCompositeOpClass` | `on` | Use the ordered composite opclass for new index builds. Long-term compatibility flag. |
| `documentdb.enableCompositeIndexPlanner` | `off` | Enable planner improvements for ordered/composite indexes. Pending stabilization. |
| `documentdb.enableIndexOnlyScan` | `on` | Allow index-only scans when the index covers all projected fields. |
| `documentdb.enableIndexOnlyScanOnCost` | `on` | Enable index-only scan via the cost function rather than always choosing it. |
| `documentdb.enableIndexOnlyScanForCoveredAggregateTargets` | `on` | Apply index-only scan for aggregate target-list expressions on covered paths. |
| `documentdb.enableIndexOnlyScanForRangeMatch` | `on` | Apply index-only scan for range-match qualifiers on covered index paths. |
| `documentdb.enableIndexOnlyScanForFindProject` | `off` | Apply index-only scan for `find` with projection. Pending stabilization. |
| `documentdb.enableOrderByIdOnCostFunction` | `off` | Use cost function to decide whether to push an `ORDER BY _id` to the index. Pending stabilization. |
| `documentdb.enableValueOnlyIndexTerms` | `on` | Generate value-only index terms (no path prefix). Long-term compatibility flag. |
| `documentdb.useNewUniqueHashEqualityFunction` | `on` | Use the updated hash equality implementation for unique indexes. |
| `documentdb.enableCompositeUniqueHash` | `on` | Enable composite hash equality for unique indexes. |
| `documentdb.enableFailureOnParallelIndexArrays` | `off` | Reject parallel arrays in composite indexes instead of silently allowing them. Pending stabilization. |
| `documentdb.emitEnableOrderedIndexFalseInResponse` | `on` | Include `"enableOrderedIndex": false` in `listIndexes` for indexes whose `enableCompositeTerm` was explicitly set to `-1`. |
| `documentdb.enableCompositeReducedCorrelatedTerms` | `off` | Reduce term generation for correlated composite index paths. Pending stabilization. |
| `documentdb.enableUniqueCompositeReducedCorrelatedTerms` | `off` | Reduce term generation for correlated composite paths on unique indexes. Pending stabilization. |
| `documentdb.enableCompositeReducedCorrelatedTermsOnCommonSubPath` | `on` | Reduce correlated composite terms on common sub-paths. |
| `documentdb.enableCompositeReducedCorrelatedPrefixTrim` | `on` | Trim prefix groups when reducing secondary variable bounds for correlated composite indexes. |
| `documentdb.enableCompositeShardDocumentTerms` | `on` | Generate shard hash terms for composite indexes (required for correct null handling). Long-term compatibility flag. |
| `documentdb.enablePartialMatchHasRecheck` | `on` | Enable recheck pass for partial index matches. |
| `documentdb.enableSkipDottedFieldIndexTerms` | `on` | Skip generating index terms for fields whose name contains a literal dot (e.g., `"a.b"`). |
| `documentdb.enableOrderedCompositeOperatorScan` | `on` | Use the single ordered scalar-array operator scan, which includes built-in skip-scan support. |
| `documentdb.enableRegexPrefixIndexBounds` | `on` | Compute tighter index bounds for anchored-prefix regex queries. |
| `documentdb.enableExtendedIndexes` | `off` | Enable the extended index feature. Pending stabilization. |
| `documentdb.enableComparableTerms` | `off` | Enable comparable index terms. Pending stabilization. |
| `documentdb.enableOrderByIndexTerm` | `off` | Enable the `ORDER BY` index term feature. Pending stabilization. |
| `documentdb.enableGroupByCompoundIdIndexPushdown` | `off` | Decompose compound `_id` in `$group` for index pushdown. Pending stabilization. |

### Query Planner

| GUC name | Default | Description |
|---|---|---|
| `documentdb.enableExprLookupIndexPushdown` | `on` | Push expression and lookup predicates down to the index. |
| `documentdb.enableNewMinMaxAccumulators` | `off` | Use the optimized min/max aggregate accumulator implementation. Pending stabilization. |
| `documentdb.enableNewWithExprAccumulators` | `off` | Use the optimized `WithExpr` accumulator for `min`, `max`, `sum`, `avg`, `first`, and `last`. Pending stabilization. |
| `documentdb.enablePerCollectionPlannerStatistics` | `off` | Maintain per-collection planner statistics for improved plan quality. Pending stabilization. |
| `documentdb.enablePlannerStatisticsNewCollections` | `off` | Apply custom planner statistics automatically to all newly created collections. Pending stabilization. |
| `documentdb.enableIndexPathKeySummarization` | `on` | Summarize index path keys to reduce plan size. |

### Aggregation & Cursors

| GUC name | Default | Description |
|---|---|---|
| `documentdb.enablePrimaryKeyCursorScan` | `off` | Use a primary-key scan for streaming cursors instead of a sequential scan. Pending stabilization. |
| `documentdb.enableContinuationFastBitmapLookup` | `off` | Skip bitmap records by TID without loading the heap when seeking the cursor continuation point. Pending stabilization. |
| `documentdb.useFileBasedPersistedCursors` | `off` | Persist cursor state to disk files rather than in-memory. Pending stabilization. |
| `documentdb.failOnGroupIdDuplicate` | `off` | Fail when a `$group` stage receives duplicate `_id` values. Pending stabilization. |
| `documentdb.enableDelayedHoldPortal` | `on` | Delay holding the portal open until there is confirmed additional data to fetch. |
| `documentdb.enableStreamingCursorDrainViaDestReceiver` | `on` | Use a direct-executor `DestReceiver` for streaming cursor drainage rather than SPI. |
| `documentdb.enableRumCursorDynamicIndexScans` | `on` | Enable dynamic index scans for RUM-backed cursors. |
| `documentdb.enableRumDynamicIndexScansSkipToTid` | `on` | Skip directly to a TID during dynamic RUM index scans. |
| `documentdb.enableDollarInToScalarArrayOpExprConversion` | `on` | Convert `$in` predicates with a scalar array to an `OpExpr` for faster plan generation. |
| `documentdb.enableUseForeignKeyLookupInline` | `on` | Use an inlined foreign-key strategy for `$lookup`. |
| `documentdb.enableAddToSetAggregationRewrite` | `on` | Use the rewritten `$addToSet` implementation (prevents crashes with `enableDelayedHoldPortal`). |
| `documentdb.inlineChangeStreamMatchStage` | `on` | Inline `$match` stages adjacent to `$changeStream` into the change-stream filter. |
| `documentdb.removeMatchNamespaceFilters` | `on` | Remove namespace `$match` filters that are inlined with `$changeStream`. |
| `documentdb.enableDynamicCursors` | `off` | Enable dynamic cursors for aggregation query rewrites. Pending stabilization. |
| `documentdb.enableGroupSubqueryElimination` | `on` | Eliminate subquery migration in `$group` by inlining `bson_repath_and_build`. |
| `documentdb.failOnNonEmptyGroupCountArg` | `off` | Fail when the `$count` accumulator in `$group` receives a non-empty argument. Pending stabilization. |
| `documentdb.enableSortGroupStage` | `on` | Enable the `$sortGroup` aggregation stage. |
| `documentdb.enableSortPushToAccumulatorWithPrefix` | `off` | Push suffix sort keys into the accumulator when group keys are a prefix of sort keys in `$sortGroup`. Pending stabilization. |
| `documentdb.enableDuplicateFieldFix` | `on` | Fix duplicate-field handling in `$addToSet`. |
| `documentdb.enableObjectIdFuncExprConversion` | `on` | Convert `ObjectId()` function calls to constant `FuncExpr` nodes for better index utilization. |
| `documentdb.enableIdIndexPushdownForQueryOp` | `on` | Push `_id` predicates down to the `_id` index. |
| `documentdb.enableBinarySearchForOrderedMove` | `on` | Use binary search when repositioning a document in an ordered array. |
| `documentdb.multipleDollarPositionalNotAllowed` | `on` | Reject update paths that contain more than one `$` positional operator (e.g., `a.$.b.$`). |

### Let / Variables

| GUC name | Default | Description |
|---|---|---|
| `documentdb.EnableOperatorVariablesInLookup` | `on` | Support `$map` `as`-alias operator variables in `let` variable expressions. |

### Collation

| GUC name | Default | Description |
|---|---|---|
| `documentdb.skipFailOnCollation` | `off` | Ignore errors when collation is specified but not yet fully supported. Pending stabilization. |
| `documentdb.enableLookupIdJoinOptimizationOnCollation` | `off` | Apply `_id`-join optimization for `$lookup` even when collation is active. Only safe when `_id` values contain no collation-sensitive types (UTF-8 strings, documents). Pending stabilization. |
| `documentdb.enableCollationWithNonUniqueOrderedIndexes` | `off` | Support collation on non-unique ordered/composite indexes. Pending stabilization. |
| `documentdb.enableCollationWithNewGroupAccumulators` | `off` | Enable collation-aware grouping with the new accumulator implementations. Pending stabilization. |

### Cluster Administration & DDL

| GUC name | Default | Description |
|---|---|---|
| `documentdb.enableLocalRetryTable` | `on` | Use a single local retry table rather than per-collection distributed retry tables. |
| `documentdb.enableSchemaEnforcementForCSFLE` | `on` | Enforce schema validation for Client-Side Field Level Encryption (CSFLE). |
| `documentdb.usePgStatsLiveTuplesForCount` | `on` | Use `pg_stat_all_tables.n_live_tup` as the fast-path count in `collStats`. |
| `documentdb.enablePrepareUnique` | `on` | Enable `prepareUnique` within `collMod`. |
| `documentdb.enableCollModUnique` | `on` | Enable setting `unique: true` via `collMod`. |
| `documentdb.enableUniqueReindex` | `off` | Enable unique reindex support. Pending stabilization. |
| `documentdb.enableCompactVacuumFull` | `off` | Run `VACUUM FULL` when `compact` is called. When `off`, `compact` is a no-op. Pending stabilization. |
| `documentdb.enableDropInvalidIndexesOnReadOnly` | `on` | Drop invalid indexes even when the database is in read-only mode. |
| `documentdb.enableOnlyCollectionCacheInvalidateOnCollectionChanges` | `on` | Only invalidate the collection cache entry on collection-level DDL rather than purging the whole database cache. |
| `documentdb.enableNewNamespaceValidation` | `off` | Use stricter namespace validation rules. Pending stabilization. |

### Change Streams

| GUC name | Default | Description |
|---|---|---|
| `documentdb.enablePreImages` | `off` | Log the full pre-image of each changed row in WAL messages for `changeStream` pre-image support. Pending stabilization. |

### Background Index Builds

| GUC name | Default | Description |
|---|---|---|
| `documentdb.indexBuildsScheduledOnBgWorker` | `off` | Schedule index builds through the background worker rather than running them inline. Pending stabilization. |

### TTL

| GUC name | Default | Description |
|---|---|---|
| `documentdb.createTTLIndexAsCompositeByDefault` | `on` | Always create new TTL indexes as composite indexes. |
| `documentdb.enableDeadIndexEntryMarkingByTTLTask` | `off` | Mark dead index entries during TTL scans to avoid redundant heap fetches. Pending stabilization. |
| `documentdb.TTLSkipCaughtUpIndexes` | `on` | Skip a TTL index for the remainder of a task invocation once it is caught up. |

---

## System Configuration

Long-term parameters that control system limits and core behavior. All are
`USERSET` unless the Scope column says otherwise.

| GUC name | Default | Range | Scope | Description |
|---|---|---|---|---|
| `documentdb.localhost_connection_string` | `host=localhost` | — | `SUSET` | libpq connection string fragment used when the server connects back to itself. |
| `documentdb.enable_create_collection_on_insert` | `on` | — | `USERSET` | Automatically create a collection when inserting into a non-existent namespace. |
| `documentdb.enableDbNameValidation` | `on` | — | `USERSET` | Enforce that the `$db` field in the command body matches the database argument. |
| `documentdb.query_plan_cache_size` | `100` | 1–∞ | `USERSET` | Maximum number of cached query plans. |
| `documentdb.maxWriteBatchSize` | `25000` | 1–∞ | `USERSET` | Maximum write operations allowed in a single write batch. |
| `documentdb.batchWriteSubTransactionCount` | `512` | 1–∞ | `USERSET` | Sub-transaction size for bulk write operations. |
| `documentdb.batchUpdateLockTimeoutMs` | `20` | 0–∞ | `USERSET` | Lock timeout in milliseconds for each bulk update sub-transaction. |
| `documentdb.coll_stats_count_policy_threshold` | `10000` | 1–∞ | `USERSET` | Below this document count, `collStats` counts documents at query time rather than using statistics. |
| `documentdb.geo2dsphereSegmentMaxLength` | `500` | 0–6372 | `USERSET` | Maximum segment length in kilometres for `2dsphere` index queries. Set to `0` to disable segmentation. |
| `documentdb.geo2dsphereSegmentMaxVertices` | `8` | 0–32 | `USERSET` | Maximum vertices per segment for `2dsphere` queries (no effect when `geo2dsphereSegmentMaxLength` is `0`). |
| `documentdb.maxIndexesPerCollection` | `64` | 0–300 | `USERSET` | Maximum number of indexes allowed on a single collection. |
| `documentdb.maxWildcardIndexKeySize` | `200` | 1–∞ | `USERSET` | Maximum key size for wildcard index terms. |
| `documentdb.maxSchemaValidatorSize` | `10240` | 0–16777216 | `USERSET` | Maximum byte size of a JSON schema validator document. |
| `documentdb.sharding_max_chunks` | `128` | 1–8192 | `USERSET` | Maximum chunks allowed for a `shardCollection` operation. |
| `documentdb.scramDefaultSaltLen` | `28` | 1–64 | `SUSET` | Default SCRAM salt length in bytes. |
| `documentdb.maxUserLimit` | `100` | 1–500 | `SUSET` | Maximum number of database users. |
| `documentdb.maxCustomCommandTimeoutLimit` | `10800000` | 0–∞ | `SUSET` | Maximum custom command timeout in milliseconds (default: 3 hours). |
| `documentdb.tdigestCompressionAccuracy` | `1500` | 10–10000 | `USERSET` | T-digest centroid count for `$percentile`/`$median`. Higher values are more accurate but use more memory. |
| `documentdb.blockedRolePrefixList` | `""` | — | `USERSET` | Comma-separated list of role-name prefixes that cannot be created or dropped. |
| `documentdb.current_op_application_name` | `""` | — | `USERSET` | Track `currentOp` only for connections with this application name. Empty string means track all. |
| `documentdb.aggregation_stages_limit` | `1000` | 1000–5000 | `USERSET` | Maximum pipeline stages permitted in a single aggregation. |
| `documentdb.index_term_compression_threshold` | `INT_MAX` | 128–∞ | `USERSET` | Index terms larger than this byte threshold are stored compressed. |
| `documentdb.enableUserCrud` | `on` | — | `USERSET` | Enable user create/read/update/delete through the data plane. |
| `documentdb.enableTTLJobsOnReadOnly` | `off` | — | `USERSET` | Allow TTL background jobs to run on read-only nodes (overrides `default_transaction_readonly` for TTL only). |
| `documentdb.enable_force_push_geonear_index` | `on` | — | `USERSET` | Always push `$geoNear` queries to the geospatial index regardless of planner cost. |
| `documentdb.forceUseIndexIfAvailable` | `on` | — | `USERSET` | Force the planner to pick the RUM index path when applicable, ignoring cost estimates. |
| `documentdb.IsPgReadOnlyForDiskFull` | `off` | — | `USERSET` | Internal flag indicating Postgres has entered read-only mode due to disk full. |
| `documentdb.throwDeadlockOnCRUD` | `off` | — | `USERSET` | Surface deadlocks as exceptions instead of writing them into the result BSON. |
| `documentdb.vectorPreFilterIterativeScanMode` | `relaxed_order` | `off`, `relaxed_order`, `strict_order` | `USERSET` | Iterative-scan strategy for vector pre-filter. `relaxed_order` allows slightly out-of-order results for better recall; `strict_order` guarantees exact distance ordering. |
| `documentdb.defaultCursorFirstPageBatchSize` | `101` | 1–∞ | `USERSET` | Batch size for the first page of a cursor response. |
| `documentdb.enableExtendedExplainPlans` | `off` | — | `USERSET` | Include additional internal detail in `explain` output. |
| `documentdb.defaultCursorExpiryTimeLimitSeconds` | `60` | 1–3600 | `USERSET` | Idle cursor lifetime in seconds. |
| `documentdb.maxCursorIntermediateFileSizeMB` | `4096` | 1–∞ | `USERSET` | Maximum size in MB of a cursor intermediate file (when `useFileBasedPersistedCursors` is on). |
| `documentdb.maxCursorFileCount` | `5000` | 0–∞ | `USERSET` | Maximum number of cursor files on disk. Set to `0` to disable the limit. |
| `documentdb.rum_library_load_option` | `none` (PG < 18) / `require_documentdb_extended_rum` (PG ≥ 18) | `none`, `prefer_documentdb_extended_rum`, `require_documentdb_extended_rum` | `POSTMASTER` | Controls how the RUM index library is loaded at server start. |
| `documentdb.enableStatementTimeout` | `on` | — | `USERSET` | Enable per-statement backend timeout override. |
| `documentdb.alternate_index_handler_name` | `""` | — | `USERSET` | Use this index handler instead of `rum` (advanced override). |
| `documentdb.max_non_ordered_term_scan_threshold` | `500` | -1–∞ | `USERSET` | Maximum terms considered for a non-ordered term scan. |

---

## Background Job Configuration

| GUC name | Default | Range | Scope | Description |
|---|---|---|---|---|
| `documentdb.maxTTLDeleteBatchSize` | `1000` | 1–∞ | `USERSET` | Maximum document deletes per TTL purger batch. |
| `documentdb.logTTLProgressActivity` | `off` | — | `USERSET` | Log TTL purger activity (verbose; off by default to reduce noise). |
| `documentdb.enableTTLBatchObservability` | `on` | — | `USERSET` | Emit TTL batch metrics for observability. |
| `documentdb.useIndexHintsForTTLTask` | `on` | — | `USERSET` | Force an ordered index scan via index hints in the TTL task. |
| `documentdb.TTLPurgerStatementTimeout` | `60000` | 1–∞ | `USERSET` | Statement timeout in milliseconds for TTL purger delete queries. |
| `documentdb.TTLTaskMaxRunTimeInMS` | `60000` | 1–∞ | `USERSET` | Total time budget in milliseconds for a single TTL task invocation. |
| `documentdb.repeatPurgeIndexesForTTLTask` | `on` | — | `USERSET` | Continue deleting in batches until `TTLTaskMaxRunTimeInMS` is reached per TTL task invocation. |
| `documentdb.skipRepeatDeleteForUnOrderedIndex` | `on` | — | `USERSET` | Use a larger single batch instead of repeated small deletes for unordered TTL indexes. |
| `documentdb.maxTTLBatchSizeUnorderedIndex` | `10000` | 1–∞ | `USERSET` | Maximum delete batch size for unordered TTL index scans. |
| `documentdb.SingleTTLTaskTimeBudget` | `20000` | 1–∞ | `USERSET` | Time budget in milliseconds for a single pass through all eligible TTL indexes. |
| `documentdb.TTLPurgerLockTimeout` | `10000` | 1–∞ | `USERSET` | Lock timeout in milliseconds for TTL purger delete queries. |
| `documentdb.enableTTLDescSort` | `off` | — | `USERSET` | Use descending sort on the TTL field when scanning indexes. Pending stabilization. |
| `documentdb.maxNumActiveUsersIndexBuilds` | `2` | 1–∞ | `USERSET` | Maximum concurrent user-initiated index builds. |
| `documentdb.maxIndexBuildAttempts` | `3` | 1–32767 | `USERSET` | Maximum retry attempts for a failed index build. |
| `documentdb.indexBuildScheduleInSec` | `2` | 1–60 | `USERSET` | Background index build cron interval in seconds. |
| `documentdb.indexQueueEvictionIntervalInSec` | `1200` | 1–∞ | `USERSET` | Interval in seconds after which skippable index build requests are evicted from the queue. |
| `documentdb.enableBackgroundWorker` | `on` | — | `POSTMASTER` | Enable the DocumentDB background worker process. |
| `documentdb.enableBackgroundWorkerJobs` | `on` | — | `USERSET` | Enable execution of the pre-defined background worker jobs. |
| `documentdb.enableBackgroundWorkerInitJobs` | `off` | — | `POSTMASTER` | Enable initialization background jobs. Pending stabilization. |
| `documentdb.backgroundWorkerJobTimeoutThresholdSec` | `300` | 1–∞ | `USERSET` | Maximum allowed background worker job timeout in seconds. |
| `documentdb.bg_worker_database_name` | `postgres` | — | `POSTMASTER` (superuser) | Database the background worker connects to. |
| `documentdb.bg_worker_latch_timeout` | `1` | 0–200 | `POSTMASTER` (superuser) | Latch timeout in seconds for the background worker leader thread. |

---

## RUM Index Configuration

The RUM index module registers its own GUCs under the same `documentdb.` prefix
(via the `documentdb_rum.` sub-prefix internally resolved to `documentdb.`).

### System / Tuning

| GUC name | Default | Range | Description |
|---|---|---|---|
| `documentdb.rum_fuzzy_search_limit` | `0` | 0–∞ | Maximum results for an exact RUM scan. `0` means no limit. |
| `documentdb.rum_default_page_fill_factor` | `50` | 10–100 | Default fill factor for RUM index pages (percentage). |
| `documentdb.rum_disable_fast_scan` | `off` | — | Disable the fast-scan optimization in RUM index reads. |
| `documentdb.parallel_index_workers_override` | `-1` | -1–∞ | Override the number of parallel workers for index builds. `-1` means use the server default. |

### Feature Flags (RUM)

| GUC name | Default | Description |
|---|---|---|
| `documentdb.rum_skip_retry_on_delete_page` | `on` | Skip retrying reads on pages being deleted during vacuum. |
| `documentdb.enable_parallel_index_build` | `on` | Enable parallel worker support during index builds. |
| `documentdb.enableSkipIntermediateEntry` | `on` | Skip intermediate entry pages during index scans. |
| `documentdb.enable_new_bulk_delete` | `on` | Use the new bulk-delete vacuum framework. |
| `documentdb.enable_overwrite_entry_tuple_on_vacuum` | `on` | Overwrite dead entry tuples during vacuum rather than delete-and-reinsert. |
| `documentdb.track_incomplete_split` | `on` | Track incomplete page splits for recovery. |
| `documentdb.fix_incomplete_split` | `on` | Repair incomplete page splits on next access. |
| `documentdb.enable_ordered_operator_scans` | `on` | Enable ordered-operator index scans. |
| `documentdb.enable_page_fill_factor` | `on` | Honor the page fill factor when writing index pages. |
| `documentdb.enable_btree_lock_order` | `on` | Use B-tree lock ordering in RUM index operations. |
| `documentdb.prune_rum_empty_pages` | `off` | Prune empty pages during vacuum. Pending stabilization. |
| `documentdb.enable_new_bulk_delete_inline_data_pages` | `off` | Delete data pages inline within the new bulk-delete vacuum framework. Pending stabilization. |
| `documentdb.enable_support_dead_index_items` | `off` | Handle `LP_DEAD` items in index scans. Pending stabilization. |
| `documentdb.vacuum_skip_prune_posting_tree_pages` | `off` | Skip pruning posting-tree pages during vacuum. |
| `documentdb.forceRumOrderedIndexScan` | `off` | Force ordered index scans (useful for testing). |

---

## How to inspect active values

```sql
-- All DocumentDB GUCs
SELECT name, setting, unit, short_desc
FROM pg_settings
WHERE name LIKE 'documentdb.%'
ORDER BY name;

-- Only feature flags (boolean, non-default)
SELECT name, setting
FROM pg_settings
WHERE name LIKE 'documentdb.%'
  AND vartype = 'bool'
  AND setting <> boot_val
ORDER BY name;
```

## Changing a parameter at runtime

```sql
-- Session-local (USERSET)
SET documentdb.enableSchemaValidation = on;

-- Persistent (requires superuser, takes effect after reload)
ALTER SYSTEM SET documentdb.maxWriteBatchSize = 50000;
SELECT pg_reload_conf();

-- Verify
SHOW documentdb.maxWriteBatchSize;
```

Parameters with `POSTMASTER` scope require a full server restart and cannot be
changed with `ALTER SYSTEM SET` at runtime.
