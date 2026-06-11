# pg_documentdb_gw_host

`pg_documentdb_gw_host` is a PostgreSQL extension that **hosts the DocumentDB gateway
as a PostgreSQL background worker**. It links the gateway library
(`documentdb_gateway_core`) directly into PostgreSQL using
[pgrx](https://github.com/pgcentralfoundation/pgrx), so the MongoDB wire-protocol
listener starts automatically when the PostgreSQL server starts — no separate daemon
required.

## What it does

- Registers a persistent background worker named `"DocumentDB Gateway Host"` that
  starts when PostgreSQL reaches a consistent state.
- Exposes two `postgresql.conf` GUC parameters for configuration:
  - `documentdb_gateway.database` — the database the gateway worker connects to
    (must be the one where `CREATE EXTENSION documentdb` was run).
  - `documentdb_gateway.setup_configuration_file` — path to the
    [SetupConfiguration.json](../pg_documentdb_gw/SetupConfiguration.json) file
    that configures the gateway's listen address, TLS, and connection pool settings.
- Restarts the background worker automatically (with a 1-second back-off) if it exits
  unexpectedly.

## Relationship to other components

```
pg_documentdb_core          foundational BSON type
      ^
      |
pg_documentdb               public DocumentDB API (CRUD, aggregation, …)
      ^
      |  (connects via PostgreSQL pool)
documentdb_gateway_core     gateway logic shared library (in pg_documentdb_gw/)
      ^
      |  (links via pgrx cdylib)
pg_documentdb_gw_host       <-- this package: bgworker host extension
```

The difference between this package and the standalone `documentdb_gateway` binary
(in `pg_documentdb_gw/`):

| | `pg_documentdb_gw_host` | standalone `documentdb_gateway` |
|---|---|---|
| Runs as | PostgreSQL background worker | Separate OS process |
| Startup | Automatic with `pg_ctl start` | Manual / process supervisor |
| Use case | Single-node / embedded deployments | Sidecar, container, or multi-node |

## Directory layout

```
pg_documentdb_gw_host/
├── Cargo.toml                   Package manifest (pgrx cdylib + embed bin)
├── pg_documentdb_gw_host.control  Extension control file
└── src/
    ├── lib.rs                   Extension entry-point (_PG_init)
    ├── bgworker.rs              Background worker registration and main loop
    ├── gucs.rs                  GUC parameter definitions
    └── bin/
        └── pgrx_embed.rs       pgrx embedding shim (required by pgrx build)
```

## Building

### Prerequisites

- Rust (edition 2021 — see `rust-toolchain.toml` in the repo root)
- [pgrx](https://github.com/pgcentralfoundation/pgrx) `0.16.0`
- A supported PostgreSQL version: 15, 16, 17, or 18

Install pgrx and initialize it for your PostgreSQL version:

```bash
cargo install cargo-pgrx --version 0.16.0
cargo pgrx init --pg16 $(which pg_config)   # adjust for your Postgres version
```

### Compile and install

From the repo root:

```bash
make install-pg_documentdb_gw_host
```

Or build directly with pgrx:

```bash
cd pg_documentdb_gw_host
cargo pgrx install --release
```

See the [build-from-source guide](../docs/build-from-source.md) for complete
prerequisites and step-by-step instructions.

## Installing

After building, load the extension into your target database:

```sql
CREATE EXTENSION pg_documentdb_gw_host;
```

Then configure the GUC parameters in `postgresql.conf` (or via `ALTER SYSTEM`):

```ini
documentdb_gateway.database = 'mydb'
documentdb_gateway.setup_configuration_file = '/etc/documentdb/SetupConfiguration.json'
```

Reload PostgreSQL to apply:

```bash
pg_ctl reload
```

The gateway worker will start and begin accepting MongoDB connections on the port
configured in `SetupConfiguration.json` (default `10260`).

## Verifying the worker is running

```sql
SELECT pid, backend_type, state
FROM pg_stat_activity
WHERE backend_type = 'DocumentDB Gateway Host';
```

You can also check the PostgreSQL log for:

```
LOG:  background worker "DocumentDB Gateway Host" started with PID ...
```

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for project-wide contribution guidelines and
[pg_documentdb_gw/CONTRIBUTING.md](../pg_documentdb_gw/CONTRIBUTING.md) for Rust-specific
conventions that also apply here (dependency declarations in workspace `Cargo.toml`,
`rustfmt`, `clippy`).
