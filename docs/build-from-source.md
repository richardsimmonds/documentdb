# Building DocumentDB from Source

This guide covers how to build DocumentDB's C extensions and Rust gateway from source,
run the test suite, and start a local server for development.

> **Quick start with Docker?** See the [README](../README.md#get-started) for the
> Docker Quickstart that gets you running in minutes without building anything locally.

---

## Contents

- [Platform support](#platform-support)
- [Prerequisites](#prerequisites)
- [Clone the repo](#clone-the-repo)
- [Install dependencies](#install-dependencies)
- [Build the C extensions](#build-the-c-extensions)
- [Build the Rust gateway](#build-the-rust-gateway)
- [Start a local server](#start-a-local-server)
- [Run tests](#run-tests)
- [Troubleshooting](#troubleshooting)

---

## Platform support

Build-from-source is supported on **Linux** (Debian/Ubuntu and RHEL/Rocky).
macOS builds are not officially tested upstream. If you are on macOS or Windows,
use the Docker quickstart instead.

PostgreSQL versions supported: **15, 16, 17, 18**

---

## Prerequisites

### System packages (Debian/Ubuntu)

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential cmake git pkg-config curl wget \
  postgresql-<PG_VERSION> postgresql-server-dev-<PG_VERSION> \
  libpq-dev libicu-dev libkrb5-dev \
  postgresql-<PG_VERSION>-pgvector \
  postgresql-<PG_VERSION>-postgis-3 \
  locales
```

Replace `<PG_VERSION>` with your target (e.g. `16`).

For PG < 18, also install the RUM extension:

```bash
sudo apt-get install -y postgresql-<PG_VERSION>-rum
```

### System packages (RHEL / Rocky Linux)

Install the PostgreSQL PGDG repository first, then:

```bash
sudo dnf install -y \
  gcc gcc-c++ make cmake git pkg-config curl \
  postgresql<PG_VERSION>-devel \
  libicu-devel krb5-devel
```

### C library dependencies

Three C libraries must be built from source and installed before building
the extensions. The repo ships helper scripts under `scripts/` for each one.

```bash
export INSTALL_DEPENDENCIES_ROOT=/tmp/install_setup
mkdir -p $INSTALL_DEPENDENCIES_ROOT

# Copy the version manifest used by all installer scripts
cp scripts/setup_versions.sh $INSTALL_DEPENDENCIES_ROOT/

# 1. libbson 1.28.0 (MongoDB C driver BSON library)
cp scripts/install_setup_libbson.sh $INSTALL_DEPENDENCIES_ROOT/
sudo INSTALL_DEPENDENCIES_ROOT=$INSTALL_DEPENDENCIES_ROOT \
     MAKE_PROGRAM=cmake \
     $INSTALL_DEPENDENCIES_ROOT/install_setup_libbson.sh

# 2. PCRE2 10.40 (Perl-compatible regular expressions)
cp scripts/install_setup_pcre2.sh $INSTALL_DEPENDENCIES_ROOT/
sudo INSTALL_DEPENDENCIES_ROOT=$INSTALL_DEPENDENCIES_ROOT \
     $INSTALL_DEPENDENCIES_ROOT/install_setup_pcre2.sh

# 3. Intel Decimal Math Library (applied/2.0u3-1)
cp scripts/install_setup_intel_decimal_math_lib.sh $INSTALL_DEPENDENCIES_ROOT/
sudo INSTALL_DEPENDENCIES_ROOT=$INSTALL_DEPENDENCIES_ROOT \
     $INSTALL_DEPENDENCIES_ROOT/install_setup_intel_decimal_math_lib.sh
```

### PostgreSQL extension dependencies

```bash
PG_VERSION=16   # change to your target version

# pg_cron
cp scripts/install_setup_pg_cron.sh $INSTALL_DEPENDENCIES_ROOT/
sudo INSTALL_DEPENDENCIES_ROOT=$INSTALL_DEPENDENCIES_ROOT \
     PGVERSION=$PG_VERSION \
     $INSTALL_DEPENDENCIES_ROOT/install_setup_pg_cron.sh

# pgvector (if not installed from packages above)
cp scripts/install_setup_pgvector.sh $INSTALL_DEPENDENCIES_ROOT/
sudo INSTALL_DEPENDENCIES_ROOT=$INSTALL_DEPENDENCIES_ROOT \
     PGVERSION=$PG_VERSION \
     $INSTALL_DEPENDENCIES_ROOT/install_setup_pgvector.sh

# PostGIS (if not installed from packages above)
sudo apt-get install -y libproj-dev libxml2-dev libjson-c-dev libgeos-dev
cp scripts/install_setup_postgis.sh $INSTALL_DEPENDENCIES_ROOT/
sudo INSTALL_DEPENDENCIES_ROOT=$INSTALL_DEPENDENCIES_ROOT \
     PGVERSION=$PG_VERSION \
     $INSTALL_DEPENDENCIES_ROOT/install_setup_postgis.sh
```

### Rust (for the gateway)

The gateway uses Rust. The required toolchain version is pinned in
`rust-toolchain.toml` (currently `1.92`).

```bash
# Install rustup if not already present
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"

# rustup will automatically pick up the pinned toolchain when you cd
# into pg_documentdb_gw; you can also install it explicitly:
rustup toolchain install 1.92 --profile minimal \
  --component rustfmt clippy cargo
```

The gateway also requires **LLVM 20** for some compilation steps:

```bash
# On Ubuntu/Debian (uses the official LLVM apt repo)
bash scripts/install_llvm.sh
```

---

## Clone the repo

```bash
git clone https://github.com/documentdb/documentdb.git
cd documentdb
```

If you are working from a fork:

```bash
git clone https://github.com/<your-fork>/documentdb.git
cd documentdb
git remote add upstream https://github.com/documentdb/documentdb.git
```

---

## Build the C extensions

The repo provides a convenience script that installs all system dependencies
and builds the three C extensions (`pg_documentdb_core`, `pg_documentdb`,
`pg_documentdb_extended_rum`) in one shot:

```bash
bash scripts/build_documentdb_with_scripts.sh --pg-version 16
```

Supported `--pg-version` values: `15`, `16`, `17`, `18`.

This script:

1. Installs build tools and system packages via `apt-get`.
2. Builds and installs libbson, PCRE2, and the Intel Decimal Math Library.
3. Installs PostgreSQL and the required extensions (pg_cron, pgvector, PostGIS, etc.).
4. Runs `make` and `sudo make install` for each extension.

After the script completes, the extensions are installed into the PostgreSQL
extension directory for the requested version, e.g.
`/usr/lib/postgresql/16/lib/`.

### Manual build

If you have already installed dependencies manually:

```bash
export PATH="/usr/lib/postgresql/<PG_VERSION>/bin:$PATH"

# Build all C extensions
make

# Install into the system PostgreSQL extension directory
sudo PATH=$PATH make install
```

Individual extension targets:

```bash
# pg_documentdb_core only
make -C pg_documentdb_core

# pg_documentdb only
make -C pg_documentdb

# pg_documentdb_extended_rum only (replacement for public RUM on PG 18+)
make -C pg_documentdb_extended_rum
```

---

## Build the Rust gateway

The gateway is a standalone Rust workspace under `pg_documentdb_gw/`.

```bash
cd pg_documentdb_gw

# Debug build (faster compile, slower execution)
cargo build

# Release build (used in production and by the start-gateway script)
cargo build --profile=release-with-symbols
```

The release binary is written to:

```
pg_documentdb_gw/target/release-with-symbols/documentdb_gateway
```

---

## Start a local server

### 1. Start PostgreSQL with the extensions loaded

Use the `start_oss_server.sh` helper from the repo root:

```bash
# First-time setup: initializes the data directory, installs extensions,
# and starts the server on port 9712
bash scripts/start_oss_server.sh -d ~/.documentdb/data -c

# Subsequent starts (no cleanup — preserves data)
bash scripts/start_oss_server.sh -d ~/.documentdb/data
```

Key options:

| Option | Description |
|--------|-------------|
| `-d <dir>` | Data directory (default: `~/.documentdb/data`) |
| `-c` | Force wipe and re-initialize |
| `-p <port>` | Backend port (default: 9712) |
| `-s` | Stop the server |
| `-e` | Allow external connections (binds to `*`) |
| `-g` | Also start the in-process gateway worker |
| `-r` | Use `pg_documentdb_extended_rum` instead of the public RUM |
| `-u <user>` | Custom admin username (default: `docdb_admin`) |
| `-a <pass>` | Password for the custom admin user (default: `Admin100`) |

### 2. Start the gateway

Once PostgreSQL is running, start the gateway in a separate terminal:

```bash
bash scripts/build_and_start_gateway.sh \
  -u docdb_admin \
  -p Admin100 \
  -P 9712
```

The gateway listens on port `10260` by default. Connect with any MongoDB
driver or `mongosh`:

```
mongodb://docdb_admin:Admin100@localhost:10260/?tls=true&tlsAllowInvalidCertificerr=true
```

> The self-signed TLS certificate used in development requires
> `tlsAllowInvalidCertificates=true` (or your driver's equivalent).

---

## Run tests

### C extension regression tests

Tests use PostgreSQL's `pg_regress` framework.

```bash
# Run the full test suite for pg_documentdb_core
make -C pg_documentdb_core check

# Run a minimal BSON-only smoke test (faster)
make -C pg_documentdb_core check-minimal

# Run pg_documentdb tests
make -C pg_documentdb check

# Run all C extension tests from the repo root
# (runs pg_documentdb_core and pg_documentdb in sequence)
make check-no-distributed
```

Tests require a running PostgreSQL instance. The test runner starts its own
temporary server using `pg_regress`, so you do not need to start one manually.

### Rust gateway tests

Integration tests in `pg_documentdb_gw/documentdb_tests/` connect to a live
PostgreSQL instance with DocumentDB installed. Start the server (see above)
before running them.

```bash
cd pg_documentdb_gw

# Run all Rust unit and integration tests
cargo test

# Run a specific integration test file
cargo test --test command_tests

# Run a specific test function
cargo test --test index_tests test_create_index
```

The test suite expects the server on localhost:9712 with the default
credentials. Set the following environment variables to override:

```bash
export DOCDB_HOST=localhost
export DOCDB_PORT=9712
export DOCDB_USER=docdb_admin
export DOCDB_PASSWORD=Admin100
```

### Code style and linting

```bash
# Rust: format check
cargo fmt --check

# Rust: lint
cargo clippy -- -D warnings

# C: indent check (requires citus_indent)
make -C pg_documentdb_core citus-indent
```

---

## Troubleshooting

**`pkg-config` cannot find libbson**

Make sure you ran the `install_setup_libbson.sh` script above and that
`/usr/lib/pkgconfig` (or your platform's equivalent) is on `PKG_CONFIG_PATH`:

```bash
export PKG_CONFIG_PATH=/usr/lib/pkgconfig:$PKG_CONFIG_PATH
pkg-config --cflags libbson-static-1.0
```

**`pg_config` not found**

Add the PostgreSQL bin directory to your PATH:

```bash
export PATH="/usr/lib/postgresql/<PG_VERSION>/bin:$PATH"
```

**`rustup` toolchain version mismatch**

The toolchain is pinned in `rust-toolchain.toml`. Running any `cargo` command
inside `pg_documentdb_gw/` will automatically install the correct toolchain
via rustup. If it fails, install it manually:

```bash
rustup toolchain install 1.92 --profile minimal
```

**Port already in use**

If port 9712 (or 10260) is occupied, pass a different port:

```bash
bash scripts/start_oss_server.sh -d ~/.documentdb/data -p 19712
bash scripts/build_and_start_gateway.sh -u docdb_admin -p Admin100 -P 19712
```

**Test failures due to locale**

The test suite requires `en_US.UTF-8`. Generate it if missing:

```bash
sudo locale-gen en_US.UTF-8
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
```
