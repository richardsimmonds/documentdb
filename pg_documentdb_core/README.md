# pg_documentdb_core

`pg_documentdb_core` is the foundational PostgreSQL extension for DocumentDB. It introduces
the **BSON data type** and a set of low-level operators, functions, and type-support
routines that the higher-level `pg_documentdb` extension depends on.

## What it does

- Registers the `bson` type so PostgreSQL can store and manipulate Binary JSON natively.
- Implements BSON I/O, comparison, and hashing routines used by indexes and queries.
- Provides collation-aware string operations for BSON fields.
- Exposes planner hooks that let the query optimizer reason about BSON expressions.
- Ships utility functions (decimal128 support, regex via PCRE2, string views) used
  throughout the DocumentDB stack.

## Relationship to other components

```
pg_documentdb_core        <-- this package
      ^
      |  (required by)
pg_documentdb             the public DocumentDB API surface (CRUD, aggregation, etc.)
pg_documentdb_gw_host     the gateway background-worker extension
```

`pg_documentdb_core` has **no extension dependencies** — it is the bottom of the stack.

## Directory layout

```
pg_documentdb_core/
├── documentdb_core.control   Extension control file
├── Makefile                  Build targets (uses pgxs)
├── include/                  Public C headers shared with pg_documentdb
│   └── utils/                Error codes, feature flags, shared macros
├── sql/                      SQL migration scripts (one per version bump)
└── src/
    ├── bson_init.c           BSON type registration and vtable
    ├── collation/            Locale-aware BSON string comparison
    ├── io/                   BSON serialization / deserialization
    ├── planner/              Query planner integration hooks
    ├── query/                BSON expression evaluation
    ├── types/                Supplemental scalar types
    │   ├── decimal128.c      IEEE 754 decimal128 arithmetic
    │   ├── pcre_regex.c      PCRE2-backed regex matching
    │   └── string_view.c     Zero-copy string slices
    └── utils/                Shared helpers (error handling, memory, etc.)
```

## Building

Build from the repo root using the top-level Makefile:

```bash
make install-pg_documentdb_core
```

Or build this extension alone (requires `pg_config` on `$PATH`):

```bash
cd pg_documentdb_core
make && sudo make install
```

See the [build-from-source guide](../docs/build-from-source.md) for full prerequisites
and step-by-step instructions.

## Installing

```sql
-- Connect to the target database, then:
CREATE EXTENSION documentdb_core;
```

`documentdb_core` has no prerequisite extensions. After installation the `bson` type is
available in all schemas.

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for the project-wide contribution guide.
This extension is written in C; follow the PostgreSQL coding style and run
`make -C pg_documentdb_core check` before submitting a PR.
