# pg_documentdb

`pg_documentdb` is the primary public API extension for DocumentDB. It sits on top of
`pg_documentdb_core` and delivers the full MongoDB-compatible document database experience
inside PostgreSQL: CRUD commands, aggregation pipelines, index management, and more.

## What it does

- Exposes the `documentdb_api` schema with functions that mirror MongoDB wire-protocol commands
  (`insert`, `find`, `update`, `delete`, `aggregate`, `createIndexes`, …).
- Manages collections and namespaces in the `documentdb_api_catalog` schema and stores
  documents in the `documentdb_data` schema.
- Implements aggregation pipeline operators, geospatial queries, full-text search, and
  vector search on BSON documents.
- Integrates with `pg_cron` for TTL (time-to-live) index expiry background jobs.
- Provides a custom scan provider so the PostgreSQL planner can push DocumentDB predicates
  into efficient index scans.
- Ships RBAC roles (`documentdb_admin_role`, `documentdb_readonly_role`,
  `documentdb_bg_worker_role`) for access control.

## Relationship to other components

```
pg_documentdb_core           foundational BSON type and low-level operators
      ^
      |  (required by)
pg_documentdb                <-- this package: public DocumentDB API
      ^
      |  (connects to via PostgreSQL)
pg_documentdb_gw             MongoDB wire-protocol gateway (Rust)
```

### Required PostgreSQL extensions

`pg_documentdb` requires the following extensions to be installed alongside it:

| Extension          | Purpose                              |
|--------------------|--------------------------------------|
| `documentdb_core`  | BSON type support                    |
| `pg_cron`          | TTL index background job scheduling  |
| `tsm_system_rows`  | Efficient random document sampling   |
| `vector`           | pgvector support for vector search   |
| `postgis`          | Geospatial query support             |

## Directory layout

```
pg_documentdb/
├── documentdb.control        Extension control file
├── Makefile                  Build targets (uses pgxs)
├── include/                  Public C headers
├── sql/                      SQL migration scripts (one per version bump)
└── src/
    ├── aggregation/          Aggregation pipeline operator implementations
    ├── auth/                 Authentication and role management helpers
    ├── background_worker/    TTL expiry and other background jobs
    ├── commands/             CRUD command handlers (insert, find, update, delete, …)
    ├── configs/              GUC (postgresql.conf) parameter definitions
    ├── customscan/           Custom scan provider for pushed-down predicates
    ├── explain/              EXPLAIN output formatting for DocumentDB plans
    ├── geospatial/           $geoNear, $geoWithin, $near, and related operators
    ├── index_am/             Index access method integration (B-tree, RUM, vector)
    ├── infrastructure/       Connection setup, schema helpers, extension init
    ├── jsonschema/           $jsonSchema validation support
    ├── metadata/             Collection and index catalog management
    ├── opclass/              BSON operator classes for index types
    ├── operators/            BSON comparison and logical operators
    ├── planner/              Query rewriting and plan transformation hooks
    ├── query/                Query parsing and execution
    ├── sharding/             Sharding metadata stubs (for distributed deployments)
    ├── ttl/                  TTL index expiry background worker
    ├── update/               Update operator implementations ($set, $push, …)
    ├── vector/               Vector search integration (pgvector)
    └── utils/                Shared utilities
```

## Building

Build from the repo root:

```bash
make install-pg_documentdb
```

Or build this extension alone (requires `pg_config` on `$PATH` and prerequisite
extensions already installed):

```bash
cd pg_documentdb
make && sudo make install
```

See the [build-from-source guide](../docs/build-from-source.md) for full prerequisites
and step-by-step instructions.

## Installing

```sql
-- Connect to the target database, then:
CREATE EXTENSION documentdb CASCADE;
```

The `CASCADE` flag automatically installs `documentdb_core` and the other required
extensions if they are not already present.

## Quick example

```python
import pymongo

client = pymongo.MongoClient(
    "mongodb://user:password@localhost:10260/?authMechanism=SCRAM-SHA-256",
    tls=True,
    tlsAllowInvalidCertificates=True,
)

db = client["mydb"]
db.products.insert_one({"name": "Widget", "price": 9.99, "tags": ["sale", "new"]})

for doc in db.products.find({"tags": "sale"}):
    print(doc)
```

Or directly via SQL:

```sql
SELECT documentdb_api.insert_one(
  'mydb', 'products',
  '{"name": "Widget", "price": 9.99, "tags": ["sale", "new"]}'::documentdb_core.bson
);
```

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for the project-wide contribution guide.
This extension is written in C; follow the PostgreSQL coding style and run
`make -C pg_documentdb check` before submitting a PR.
