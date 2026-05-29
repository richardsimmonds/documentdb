# DocumentDB Architecture Overview

This document explains how DocumentDB's components fit together: the data flow from a MongoDB client all the way down to PostgreSQL storage, how the wire protocol is translated, and how the BSON type system maps to PostgreSQL.

## Table of Contents

- [High-Level Overview](#high-level-overview)
- [Components](#components)
  - [pg_documentdb_core](#pg_documentdb_core)
  - [pg_documentdb](#pg_documentdb)
  - [pg_documentdb_gw](#pg_documentdb_gw)
  - [pg_documentdb_gw_host](#pg_documentdb_gw_host)
- [Data Flow](#data-flow)
- [Wire Protocol Translation](#wire-protocol-translation)
- [BSON to PostgreSQL Type System](#bson-to-postgresql-type-system)
- [Deployment Topologies](#deployment-topologies)

---

## High-Level Overview

DocumentDB layers three PostgreSQL extensions on top of a standard PostgreSQL instance:

```
MongoDB Client
      |  (MongoDB wire protocol, port 10260 by default)
      v
pg_documentdb_gw  (Rust — async gateway process)
      |  (libpq / PostgreSQL wire protocol)
      v
PostgreSQL
  ├── pg_documentdb       (C extension — public API, CRUD, aggregation, indexes)
  └── pg_documentdb_core  (C extension — BSON data type and low-level ops)
```

A MongoDB driver connects to the gateway exactly as it would connect to MongoDB. The gateway parses the MongoDB wire protocol, authenticates the request, translates it into SQL or a DocumentDB stored-procedure call, and forwards it to PostgreSQL over a standard libpq connection. Results come back as BSON documents and are serialized back to the MongoDB wire format before being returned to the client.

---

## Components

### pg_documentdb_core

**Language:** C  
**Location:** `pg_documentdb_core/`

This is the foundation. It introduces the `bson` data type to PostgreSQL and provides all the low-level primitives that the other extensions build on.

Key responsibilities:

- **BSON data type (`pgbson`)**: A PostgreSQL varlena type that stores a raw BSON document as bytes. Defined in `include/io/pgbson.h`. Supports the usual PostgreSQL input/output functions, comparison operators, and hashing so BSON values can be indexed and sorted.
- **BSON element traversal**: Functions to iterate over BSON documents, follow dotted paths (e.g. `"a.b.c"`), and extract values by type.
- **Memory management**: Hooks libbson's allocator into PostgreSQL's `palloc`/`pfree` via `InstallBsonMemVTablesLocal()`. Each shared library that links libbson statically calls this at `_PG_init` to ensure its private copy uses palloc rather than system malloc.
- **Type coercion helpers**: Functions to read BSON values as `int32`, `int64`, `double`, `bool`, `Decimal128`, etc., and convert between BSON types and PostgreSQL types.
- **Collation support**: BSON-aware string collation (ICU-backed) for comparison and sorting.
- **Utility modules**: PCRE-based regex, string views, decimal-128 arithmetic (backed by Intel's libbid).

`pg_documentdb_core` has no knowledge of collections, databases, or MongoDB semantics. It only knows about individual BSON documents and values.

### pg_documentdb

**Language:** C  
**Location:** `pg_documentdb/`

This extension implements the MongoDB-compatible API surface. It is the public face of DocumentDB — all MongoDB operations (find, insert, update, delete, aggregate, createIndex, etc.) are implemented here as PostgreSQL stored procedures and functions.

Key responsibilities:

- **CRUD operations**: `insert`, `find` (with cursors), `update`, `delete`, `findAndModify`.
- **Aggregation pipeline**: `$match`, `$project`, `$group`, `$sort`, `$lookup`, `$unwind`, and many other stages, implemented as SQL-generating C code.
- **Index management**: Background index creation, compound indexes, partial indexes, text indexes, geospatial (2dsphere) indexes, and vector (HNSW/IVFFlat) indexes — all backed by native PostgreSQL index AM extensions.
- **Collection and database lifecycle**: create/drop collections and databases, collection metadata.
- **Schema validation**: JSON Schema-based document validation.
- **Query planner hooks**: Custom scan nodes and planner hooks that let PostgreSQL understand BSON operator expressions and choose appropriate indexes.
- **TTL background worker**: Automatic document expiration.
- **Sharding stubs**: Entry points for collection-level sharding (used by the managed service; stubs in OSS).
- **Auth**: SCRAM-SHA-256 and role-based access control, exposed as SQL functions that the gateway calls.

`pg_documentdb` depends on `pg_documentdb_core` for the BSON type but adds all collection/document-level semantics.

### pg_documentdb_gw

**Language:** Rust (async, Tokio)  
**Location:** `pg_documentdb_gw/`

This is the protocol gateway. It listens on a TCP (or Unix domain) socket for incoming MongoDB wire protocol connections, parses them, and translates them to calls against PostgreSQL via libpq.

Internal crates:

| Crate | Role |
|---|---|
| `documentdb_gateway_core` | All logic: protocol parsing, request processing, Postgres client, auth, cursors |
| `documentdb_gateway` | Standalone binary — reads a `SetupConfiguration.json` and starts the gateway as an external process |
| `documentdb_gateway_lib` | Library entry point for embedding in other runtimes |
| `documentdb_macros` | Proc-macro helpers used internally |
| `documentdb_tests` | Integration tests |

Key subsystems inside `documentdb_gateway_core`:

- **`protocol/`**: MongoDB wire protocol parser. Handles `OP_MSG` (the modern framing) as well as legacy opcodes (`OP_QUERY`, `OP_INSERT`, etc.). Reads the 4-byte length-prefixed BSON documents off the wire into typed `MessageSection` values.
- **`requests/`**: Turns the raw parsed message into a typed `Request` with a `RequestType` (e.g. `Find`, `Insert`, `Aggregate`, `CreateIndexes`). Extracts cross-cutting fields: `$db`, collection name, `lsid` (logical session ID), `maxTimeMS`, read concern, transaction info.
- **`processor/`**: Routes each `RequestType` to a handler (`data_management.rs`, `indexing.rs`, `data_description.rs`, `cursor.rs`, etc.). Each handler builds the SQL or calls the right DocumentDB stored procedure via the `PgDataClient` trait.
- **`postgres/`**: Manages PostgreSQL connections (`conn_mgmt/`), runs queries, maps errors, and holds a `QueryCatalog` (a catalog of parameterized SQL query strings loaded at startup from `SetupConfiguration.json`).
- **`auth/`**: SCRAM-SHA-256 authentication handshake, forwarding credentials to `pg_documentdb`'s auth functions.
- **`context/`**: Per-connection (`ConnectionContext`) and per-request (`RequestContext`) state — current user, cursor table, transaction state, dynamic configuration.
- **`responses/`**: Serializes Postgres result rows back to BSON `OP_MSG` responses.

### pg_documentdb_gw_host

**Language:** Rust (pgrx)  
**Location:** `pg_documentdb_gw_host/`

This crate packages the gateway as a **PostgreSQL background worker** using [pgrx](https://github.com/pgcentralfoundation/pgrx). In this deployment mode, the gateway runs inside the PostgreSQL process tree rather than as a separate process. At `_PG_init`, it registers a background worker that connects to the configured database via SPI and starts the Tokio async runtime.

This is how the `documentdb-local` Docker image works: PostgreSQL is the only process, and the gateway starts automatically as a background worker when PostgreSQL starts.

---

## Data Flow

### Read example: `db.orders.find({ status: "open" })`

```
1. MongoDB driver sends OP_MSG (opcode 2013) over TCP
       { find: "orders", filter: { status: "open" }, $db: "mydb" }

2. Gateway: protocol/reader.rs reads the 4-byte header + BSON payload

3. Gateway: requests/mod.rs parses RequestType::Find, extracts:
       db = "mydb", collection = "orders",
       filter = { status: "open" }

4. Gateway: processor/data_management.rs calls PgDataClient::find_cursor_first_page()
       SQL: SELECT documentdb_api.find_cursor_first_page($1::text, $2::bson, ...)

5. PostgreSQL: pg_documentdb's find_cursor_first_page() function:
   a. Looks up collection metadata
   b. Builds a query plan (uses custom scan node if an index matches)
   c. Executes: SELECT document FROM documentdb_data.mydb_orders
                WHERE document @@ '{ "status": "open" }'::bson
   d. Applies projection, sort, limit
   e. Returns first batch as a pgbson cursor document

6. Gateway: responses/ serializes cursor document back to OP_MSG BSON
       { cursor: { firstBatch: [...], id: 0, ns: "mydb.orders" }, ok: 1 }

7. OP_MSG sent back to MongoDB driver over TCP
```

### Write example: `db.orders.insertOne({ item: "widget", qty: 10 })`

```
1. OP_MSG: { insert: "orders", documents: [{item: "widget", qty: 10}], $db: "mydb" }

2. Gateway: RequestType::Insert

3. processor/data_management.rs calls insert() or insert_bulk()
       SQL: SELECT documentdb_api.insert($1::text, $2::bson, ...)

4. pg_documentdb: validates the document, assigns _id if missing,
   executes: INSERT INTO documentdb_data.mydb_orders (document)
             VALUES ('{"item":"widget","qty":10}'::bson)

5. Returns { n: 1, ok: 1 } as OP_MSG
```

---

## Wire Protocol Translation

DocumentDB's gateway implements the [MongoDB Wire Protocol](https://www.mongodb.com/docs/manual/reference/mongodb-wire-protocol/).

### Message framing

Every message starts with a 16-byte header:

```
int32  messageLength    total message size (including this header)
int32  requestID        unique identifier for this request
int32  responseTo       requestID this is replying to (0 for client messages)
int32  opCode           what kind of message this is
```

The gateway handles these opcodes:

| OpCode | Value | Description |
|---|---|---|
| `OP_MSG` | 2013 | Modern framing for all commands (MongoDB 3.6+) |
| `OP_QUERY` | 2004 | Legacy; used for `isMaster`/`hello` during handshake |
| `OP_INSERT` | 2002 | Legacy insert (deprecated) |
| `OP_COMPRESSED` | 2012 | Compressed message wrapper (Snappy/zlib/zstd) |

All modern MongoDB drivers use `OP_MSG` exclusively. The legacy opcodes remain supported for older driver compatibility.

### OP_MSG structure

```
header (16 bytes)
flagBits (uint32)       optional compression / more-to-come flags
sections[]:
  type 0: BSON document     (the command body)
  type 1: document sequence (e.g., bulk insert documents)
[checksum (uint32)]     optional CRC32C
```

### Command dispatch

The command name is the first key in the `type 0` BSON document (e.g., `"find"`, `"insert"`, `"aggregate"`). `requests/request_type.rs` maps this string to a `RequestType` enum variant. `processor/process.rs` then dispatches to the appropriate handler with a `match` on `RequestType`.

Each handler builds a SQL call into `pg_documentdb`'s stored procedures. The SQL templates are loaded from `SetupConfiguration.json` at startup into a `QueryCatalog` struct, keeping the gateway code free of hardcoded SQL strings.

### Authentication

On the first connection, the gateway performs the SCRAM-SHA-256 handshake:

1. Client sends `saslStart` with mechanism `SCRAM-SHA-256`.
2. Gateway calls `pg_documentdb`'s `authenticate_with_scram_sha256` SQL function to validate credentials stored in the PostgreSQL catalog.
3. On success, the gateway sets the connection's `AuthState` and creates an authorized `PgDataClient` with a connection pool for that user.

---

## BSON to PostgreSQL Type System

DocumentDB stores all documents as the `bson` PostgreSQL type (internally `pgbson`), which is a varlena (variable-length) type wrapping raw BSON bytes.

### pgbson

```c
typedef struct {
    int32 vl_len_;                       // PostgreSQL varlena header
    char vl_dat[FLEXIBLE_ARRAY_MEMBER];  // raw BSON bytes
} pgbson;
```

The BSON bytes are stored verbatim. There is no intermediate JSON or relational decomposition. A full document lives in a single heap column.

### BSON type to PostgreSQL mapping

| BSON type | BSON type code | PostgreSQL representation |
|---|---|---|
| Double | 0x01 | `float8` (via coercion), stored as-is in BSON |
| String | 0x02 | `text` (UTF-8) |
| Document | 0x03 | Nested `pgbson` |
| Array | 0x04 | Nested `pgbson` with integer keys |
| Binary | 0x05 | `bytea` |
| ObjectId | 0x07 | 12-byte `bytea` |
| Boolean | 0x08 | `bool` |
| Date | 0x09 | `timestamptz` (UTC milliseconds) |
| Null | 0x0A | SQL NULL |
| Regex | 0x0B | `text` pattern + flags |
| Int32 | 0x10 | `int4` |
| Timestamp | 0x11 | Internal BSON timestamp (not wall clock) |
| Int64 | 0x12 | `int8` |
| Decimal128 | 0x13 | Custom Intel libbid-based type (`Decimal128`) |
| MinKey | 0xFF | Sentinel (sorts below everything) |
| MaxKey | 0x7F | Sentinel (sorts above everything) |

Coercions happen when query operators need to compare BSON values with PostgreSQL scalars, or when aggregation stages produce intermediate values. The coercion functions live in `pg_documentdb_core/src/types/` and `pg_documentdb_core/include/types/`.

### Decimal128

MongoDB's `Decimal128` type (IEEE 754-2008 128-bit decimal) is implemented on top of Intel's Binary Integer Decimal (libbid) library. The `pg_documentdb_core` extension wraps all arithmetic, comparison, and conversion operations so Decimal128 behaves correctly under the full BSON comparison order, including `NaN`, `Infinity`, and denormal values.

### Indexes

Because documents are stored as opaque BSON, indexes require expression-level operators:

- **`@@ bson` operator**: Evaluates a BSON query filter against a document. The planner hooks in `pg_documentdb` translate this into an index scan when a suitable index exists.
- **Expression indexes**: For fields frequently filtered or sorted, DocumentDB creates PostgreSQL expression indexes that extract a typed scalar from the BSON column.
- **Full-text**: Mapped to PostgreSQL `tsvector`/`tsquery`.
- **Geospatial**: `2dsphere` queries mapped to PostGIS or built-in geometry operators.
- **Vector search**: HNSW and IVFFlat indexes via the `pg_documentdb_extended_rum` extension, backed by `pgvector`-compatible operators.

### Storage schema

Each collection is backed by a PostgreSQL table in the `documentdb_data` schema:

```sql
CREATE TABLE documentdb_data.<db>_<collection> (
    shard_key_value  bigint,
    object_id        bson    NOT NULL,
    document         bson    NOT NULL,
    creation_time    timestamptz DEFAULT now()
);
```

The `document` column holds the entire BSON document. Queries against arbitrary fields use the `@@` operator and expression indexes rather than individual columns — the schema is schema-less from the application's perspective.

---

## Deployment Topologies

### Standalone (documentdb-local Docker image)

```
[PostgreSQL process]
  ├── pg_documentdb_core  (loaded via shared_preload_libraries)
  ├── pg_documentdb        (loaded via shared_preload_libraries)
  └── pg_documentdb_gw_host background worker
        └── Tokio runtime — listens on port 10260
```

The gateway background worker connects back to PostgreSQL over a Unix domain socket (loopback, no extra network hop). This is the topology used by the `documentdb-local` Docker image.

### External gateway (standalone binary)

```
[documentdb_gateway binary]  →  libpq over TCP/Unix  →  [PostgreSQL]
       Listens on :10260                                   pg_documentdb
                                                           pg_documentdb_core
```

Useful when running PostgreSQL on separate hardware or in a managed service. The gateway reads `SetupConfiguration.json` for the PostgreSQL connection string, TLS configuration, and query catalog.

### Managed service (Azure Cosmos DB for MongoDB)

The managed service adds a routing layer in front of multiple PostgreSQL nodes and uses the sharding APIs in `pg_documentdb`. The OSS extensions include the API surface; the routing and shard management logic is in the managed layer.
