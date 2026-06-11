# Contributing to DocumentDB

Thank you for your interest in contributing to DocumentDB. There are several ways through which contributions to the project can be made and you can get involved.

## Table of Contents

- [Asking Questions](#asking-questions)
- [Reporting Issues](#reporting-issues)
- [How to Contribute](#how-to-contribute)
- [Developer Workflow](#developer-workflow)
  - [Prerequisites](#prerequisites)
  - [Option A: Dev Container (recommended)](#option-a-dev-container-recommended)
  - [Option B: Build from source](#option-b-build-from-source)
  - [Repository layout](#repository-layout)
  - [Building the project](#building-the-project)
  - [Running tests](#running-tests)
  - [Running functional tests](#running-functional-tests)
  - [Adding a feature or fixing a bug](#adding-a-feature-or-fixing-a-bug)
- [Pull Requests](#pull-requests)
- [Technical Steering Committee and Maintainers](#technical-steering-committee-and-maintainers)
- [Discussion Etiquette](#discussion-etiquette)

---

## Asking Questions

[Join us on Discord](https://discord.gg/vH7bYu524D) to engage directly with our team and the community with any questions you may have. Our channel is not only a place for immediate assistance but also a hub for discussing project updates, upcoming features, and technical challenges. We host regular meetings where TSC members and contributors can interact directly to ask questions, share feedback, and discuss their ideas in real time.

## Reporting Issues

Before a new issue is created for a bug or feature request, please check the list of open issues to avoid multiple issues being created for the same bug or feature. If one already exists, add a reaction and relevant comments for additional clarity if needed.

## How to Contribute

We encourage community members to participate by reporting issues, suggesting new features, or contributing code.

### 1. General Contributions

The more descriptive the issue is and the more information that can be provided, the more helpful it will be to the community and the contributors to pick up the issue.

For each issue created, please include:

- A brief description of the suggestion or issue.
- Relevant details such as the operating system you were using, if applicable.
- Clear, step-by-step instructions or context that describe how the issue occurred or how the feature would function.
- The expected outcome versus the actual result or behavior observed, if relevant.

### Code Contributions

For those looking to contribute code, whether for bug fixes or new features, please ensure your issues and pull requests include the following:

- A code snippet that reliably reproduces the issue or demonstrates the new feature.
- An accessible repository link that can be cloned, built, and run, providing a complete environment for testing and verifying the issue or feature.
- Clear documentation or comments in the code explaining the changes made and their purpose.

---

## Developer Workflow

This section is for contributors who want to build and run DocumentDB locally, run the test suite, and understand the codebase structure.

> **Quickstart without building:** If you just want to run DocumentDB locally to try it out, use the Docker image. See [README.md](./README.md#get-started) for instructions.

### Prerequisites

- **Git**
- **Docker** (required for the dev container path and for functional tests)
- **VS Code with the Dev Containers extension** (for Option A)
- **Linux (Debian/Ubuntu or RHEL/Rocky)** if building from source directly (Option B). macOS and Windows are not officially tested for source builds — use the dev container instead.

### Option A: Dev Container (recommended)

The repository ships a fully configured dev container in `.devcontainer/` that
provides all build dependencies, PostgreSQL, Rust, and VS Code extensions
pre-installed. This is the fastest way to get a working build environment.

**Steps:**

1. Install [VS Code](https://code.visualstudio.com/) and the
   [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers).

2. Clone the repo:

   ```bash
   git clone https://github.com/documentdb/documentdb.git
   cd documentdb
   ```

3. Open in VS Code and reopen in the container when prompted:

   ```
   Cmd/Ctrl+Shift+P → "Dev Containers: Reopen in Container"
   ```

   The container builds on first launch (a few minutes). Subsequent opens are
   fast because the image layer is cached.

4. Once inside the container, build the extensions:

   ```bash
   make install-documentdb
   ```

The dev container defaults to **PostgreSQL 16** with Citus. To use a different
PostgreSQL version, edit `.devcontainer/devcontainer.json` and set the
`PG_VERSION` build arg before rebuilding the container.

The container forwards two ports to your host:

| Port  | Service                        |
|-------|--------------------------------|
| 9712  | PostgreSQL (direct connection) |
| 10260 | DocumentDB gateway (MongoDB wire protocol) |

### Option B: Build from source

For detailed instructions on building DocumentDB dependencies and extensions
from scratch on a Linux host, see [docs/build-from-source.md](./docs/build-from-source.md).

---

### Repository layout

```
documentdb/
├── pg_documentdb_core/     # PostgreSQL extension: BSON datatype, core operators
│   ├── src/                # C source — types/, io/, query/, planner/
│   └── sql/                # SQL function definitions, upgrade scripts
├── pg_documentdb/          # PostgreSQL extension: public DocumentDB API (CRUD, indexes, etc.)
│   ├── src/                # C source — commands/, aggregation/, geospatial/, auth/, …
│   └── sql/                # SQL functions and views
├── pg_documentdb_gw/       # Rust workspace: MongoDB-wire-protocol gateway
│   ├── documentdb_gateway/ # Core gateway protocol handler
│   ├── documentdb_gateway_core/
│   ├── documentdb_gateway_lib/
│   ├── documentdb_macros/  # Proc macros
│   └── documentdb_tests/   # Integration tests for the gateway
├── pg_documentdb_extended_rum/ # Extended RUM index support
├── pg_documentdb_gw_host/  # pgrx host shim that links gateway into Postgres
├── documentdb-local/       # Docker image for local development
│   ├── functional-tests/   # Functional test gate (allowlist, scripts, tools)
│   └── scripts/            # Container entrypoint and helper scripts
├── .devcontainer/          # VS Code dev container definition
├── scripts/                # Dependency install and setup scripts
└── rfcs/                   # Design documents and RFCs
```

**Component relationships:**

```
MongoDB client
      │  (MongoDB wire protocol)
      ▼
pg_documentdb_gw  (Rust)  ──▶  pg_documentdb  (C / PostgreSQL extension)
                                      │
                                      ▼
                              pg_documentdb_core  (C / PostgreSQL extension)
                                      │
                               PostgreSQL storage
```

### Building the project

All build targets delegate to per-component Makefiles. From the repo root:

```bash
# Build and install all C extensions (core + api + extended rum)
make install-documentdb

# Build a specific component
make -C pg_documentdb_core install
make -C pg_documentdb install
make -C pg_documentdb_extended_rum install

# Build the Rust gateway (requires Rust toolchain from rust-toolchain.toml)
cd pg_documentdb_gw
cargo build
```

The dev container has `make` and `cargo` on `PATH`. No additional environment
setup is needed inside the container.

**Build flags:**

| Variable | Default | Effect |
|----------|---------|--------|
| `DEBUG=yes` | `no` | Adds `-ggdb -O0 -g` for the C extensions (unoptimized build with debug symbols) |
| `PG_VERSION` | from env | Selects the PostgreSQL version to build against |

For example, to build `pg_documentdb` with debug symbols:

```bash
make -C pg_documentdb DEBUG=yes install
```

### Running tests

#### C extension regression tests

Each C extension has its own `make check` target that spins up a temporary
PostgreSQL cluster, runs the test suite, and tears it down.

```bash
# Run all tests for pg_documentdb
make -C pg_documentdb check

# Run a minimal subset (faster, suitable for quick iteration)
make -C pg_documentdb check-minimal

# Run core-only tests
make -C pg_documentdb_core check

# Run extended RUM index tests
make -C pg_documentdb check-extended-rum

# Run isolation tests (concurrency / locking behavior)
make -C pg_documentdb check-isolation
```

Test results and PostgreSQL logs land in `src/test/regress/log/` inside each
component directory.

#### Rust gateway tests

```bash
cd pg_documentdb_gw

# Unit tests
cargo test

# Run a specific integration test file (requires a running DocumentDB
# instance reachable on the gateway port)
cargo test --test command_tests
```

Integration test files live in `documentdb_tests/tests/` and are organized by
command or feature area — for example `command_tests.rs`, `index_tests.rs`,
`cursor_tests.rs`, `transaction_tests.rs`, and `text_search_tests.rs`. Test
helper functions in `documentdb_tests/src/commands/` are organized as one
module per command (`insert.rs`, `find.rs`, `aggregate.rs`, …) and are consumed
by those integration tests. See
[pg_documentdb_gw/CONTRIBUTING.md](./pg_documentdb_gw/CONTRIBUTING.md) for the
gateway workspace conventions.

#### Valgrind (memory error detection)

```bash
make -C pg_documentdb check-valgrind
```

This starts a dedicated PostgreSQL on port 58070 and runs the regression suite
under Valgrind. Expect significantly longer runtimes.

### Running functional tests

The `documentdb-local/functional-tests/` directory contains the PR gate that
runs the pinned upstream compatibility suite against a locally built
`documentdb-local` Docker image.

**Prerequisites:** Docker, Python 3 with `pyyaml`.

```bash
# Run the PR-gate allowlist (tests that must pass before merging)
./documentdb-local/functional-tests/scripts/run-functional-tests.sh allowlist

# Build and start documentdb-local automatically, then run the allowlist
./documentdb-local/functional-tests/scripts/run-functional-tests.sh allowlist \
  --build-and-start-documentdb

# Run a single test by pytest node ID
./documentdb-local/functional-tests/scripts/run-functional-tests.sh single \
  --test compatibility/tests/core/query-and-write/commands/find/test_find_basic_queries.py::test_find_all_documents

# Run the full upstream suite
./documentdb-local/functional-tests/scripts/run-functional-tests.sh full --workers 4
```

If you already have a running DocumentDB instance, point the runner at it via
the `CONNECTION_STRING` environment variable:

```bash
CONNECTION_STRING="mongodb://default_user:***@localhost:10260/?tls=true&tlsAllowInvalidCertificates=true" \
  ./documentdb-local/functional-tests/scripts/run-functional-tests.sh allowlist
```

See [documentdb-local/functional-tests/README.md](./documentdb-local/functional-tests/README.md)
for the full reference including CI failure debugging and allowlist management.

### Adding a feature or fixing a bug

1. **Find or file an issue.** Search the open issues first. If none exists,
   create one describing the problem or feature before writing code.

2. **Fork and branch.** Create a feature branch from `main`:

   ```bash
   git checkout -b feat/<short-description>
   # or
   git checkout -b fix/<issue-number>-short-description
   ```

3. **Make your changes.** Keep the following in mind:

   - **C extensions (`pg_documentdb_core`, `pg_documentdb`):** Follow the
     existing code style. Run `make -C pg_documentdb check` before submitting.
     Add or update regression tests under `src/test/regress/` for any
     behavior change.

   - **Rust gateway (`pg_documentdb_gw`):** Follow the
     [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/about.html).
     Run `cargo fmt` and `cargo clippy` before submitting — CI will reject
     formatting violations and clippy warnings. All workspace dependencies go
     in the root `Cargo.toml` under `[workspace.dependencies]`; do not add
     version numbers directly in member crate `Cargo.toml` files. Add tests
     in `documentdb_tests/tests/` for new gateway commands or behaviors.

4. **Run the relevant tests.** At minimum run the regression tests for the
   component(s) you changed and the PR-gate functional tests.

5. **Sign your commits.** All commits require a DCO sign-off (see
   [Pull Requests](#pull-requests) below).

6. **Open a pull request** against `main`. Include:
   - A reference to the issue (`Fixes #N` or `Relates to #N`).
   - A description of the change and why it is correct.
   - Any manual testing steps that reviewers should follow.

---

## Pull Requests

We want to ensure all contributions made by the developer community are correctly licensed. To achieve this, DocumentDB uses a Developer Certificate of Origin (DCO). The DCO is a declaration attached to each commit to the project. A message that simply adds a Signed-off-by statement to every commit to DocumentDB is all that is needed and this confirms that the committer agrees to the DCO, which can be located at https://developercertificate.org/.

DocumentDB requires every contribution to be signed with a DCO through a known identity. Anonymous names or pseudonyms cannot be used. An example of a DCO signed commit message is:

```bash
Commit message

Signed-off-by: John Doe <john.doe@email.com>
```

Git includes a `-s` command line option to append this line automatically to your commit message (provided you have configured your `user.name` and `user.email` in your git configuration):

```bash
git commit -s -m 'Commit message'
```

Commits of any form require a DCO, including revert commits.

## Technical Steering Committee and Maintainers

DocumentDB is governed by the Technical Steering Committee, where all decisions are conducted in the open, documented, and voted upon. All code that is checked in is managed by the Maintainers. The list of TSC members and the project's maintainers are listed in the [MAINTAINERS.md](./MAINTAINERS.md) file.

## Discussion Etiquette

To provide all members of the community with a safe space for contributions and discussions, we request that comments always be courteous and respectful of others.
