# CoqHammer Workspace Setup

AGM sources `env.sh` for every workspace before running `setup.sh`.
The scripts create and use a workspace-local opam switch, so builds and
`make install` do not affect other worktrees.

## Default Behavior

By default, each workspace uses:

```bash
COQHAMMER_OPAM_SWITCH="$REPO_DIR"
COQHAMMER_OCAML="ocaml-base-compiler.5.3.0"
```

The actual opam prefix is:

```bash
$REPO_DIR/_opam
```

`env.sh` prepends `$REPO_DIR/_opam/bin` to `PATH`, so `rocq`, `coqc`,
`ocamlfind`, and related tools resolve from the workspace-local switch.

Without overrides, `setup.sh` installs dependencies from:

```bash
./coq-hammer-tactics.opam
./coq-hammer.opam
```

That means the Rocq/Coq version is selected by the opam constraints in the
checked-out branch.

## Force an Opam Rocq/Coq Version

Set these in a workspace or branch-specific `env.sh`:

```bash
export COQHAMMER_ROCQ_PACKAGE=coq
export COQHAMMER_ROCQ_VERSION=9.1.1
```

When `COQHAMMER_ROCQ_VERSION` is set, `setup.sh` first installs that exact opam
package version, then installs CoqHammer dependencies while ignoring only the
Coq/Rocq version constraints from the local opam files.

## Build Rocq From Source

Set `COQHAMMER_ROCQ_SOURCE_REF` to build Rocq from an AGM-managed git dependency
instead of using the opam Rocq/Coq package:

```bash
export COQHAMMER_ROCQ_SOURCE_REF=main
```

or:

```bash
export COQHAMMER_ROCQ_SOURCE_REF=V9.1.1
```

Defaults:

```bash
COQHAMMER_ROCQ_SOURCE_REPO="https://github.com/rocq-prover/rocq.git"
COQHAMMER_ROCQ_DEP_NAME="rocq"
COQHAMMER_ROCQ_SOURCE_DIR=""
```

Override `COQHAMMER_ROCQ_SOURCE_REPO` for a fork before the AGM dependency is
created. `setup.sh` runs `agm dep new` for the first checkout and `agm dep switch`
for additional branch/tag checkouts under `$PROJ_DIR/deps`. Set
`COQHAMMER_ROCQ_SOURCE_DIR` only to use an existing checkout outside AGM and
outside `$PROJ_DIR/deps`.

## Branch-Specific Configuration

AGM sources project config first, then branch config. For branch `B`, create:

```bash
$PROJ_DIR/config/B/env.sh
```

Examples:

```bash
export COQHAMMER_ROCQ_VERSION=9.1.1
```

```bash
export COQHAMMER_ROCQ_SOURCE_REF=main
```

Then open the workspace normally; `agm open` runs setup automatically:

```bash
agm open B
```

