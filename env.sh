# CoqHammer workspace environment.
#
# AGM sources this file for every workspace with:
#   PROJ_DIR=/home/dev/coqhammer
#   REPO_DIR=<main repo or worktree path>
#
# Keep the opam switch local to the current checkout. Opam will place the switch
# prefix at `$REPO_DIR/_opam`, and `make install` will install into that prefix.

export COQHAMMER_OPAM_SWITCH="${COQHAMMER_OPAM_SWITCH:-$REPO_DIR}"
export COQHAMMER_OCAML="${COQHAMMER_OCAML:-ocaml-base-compiler.5.3.0}"

# Rocq opam packages. Leave all unset for the normal flow, where the Rocq/Coq
# version is resolved from the opam-file constraints of the checked-out branch.
# Since the Rocq rename (Rocq >= 9.0) those constraints name rocq-core and
# rocq-stdlib; the deprecated "coq" package applies only to older (< 9.0)
# branches. Set COQHAMMER_ROCQ_PACKAGES (a space-separated "pkg[.version]" list)
# to pin Rocq explicitly when the exact version is not yet resolvable from the
# constraints alone -- e.g. rocq-core is published for X.Y but rocq-stdlib is
# not, so the newest available stdlib must be pinned. COQHAMMER_ROCQ_PACKAGE /
# COQHAMMER_ROCQ_VERSION are the legacy single-package pin (package defaults
# version-aware: rocq-core for Rocq >= 9.0, else coq).
export COQHAMMER_ROCQ_PACKAGES="${COQHAMMER_ROCQ_PACKAGES:-}"
export COQHAMMER_ROCQ_PACKAGE="${COQHAMMER_ROCQ_PACKAGE:-}"
export COQHAMMER_ROCQ_VERSION="${COQHAMMER_ROCQ_VERSION:-}"

# Leave unset for the normal opam package flow. Set to an AGM-managed branch or
# tag before running `agm workspace setup` to build Rocq from source in this switch.
export COQHAMMER_ROCQ_SOURCE_REF="${COQHAMMER_ROCQ_SOURCE_REF:-}"
export COQHAMMER_ROCQ_SOURCE_REPO="${COQHAMMER_ROCQ_SOURCE_REPO:-https://github.com/rocq-prover/rocq.git}"
export COQHAMMER_ROCQ_DEP_NAME="${COQHAMMER_ROCQ_DEP_NAME:-rocq}"
export COQHAMMER_ROCQ_SOURCE_DIR="${COQHAMMER_ROCQ_SOURCE_DIR:-}"

# Since Rocq 9.0 the standard library lives in a separate repository and must be
# built alongside a source build of Rocq. These only take effect when
# COQHAMMER_ROCQ_SOURCE_REF is set; the ref defaults to the Rocq source ref.
export COQHAMMER_STDLIB_SOURCE_REF="${COQHAMMER_STDLIB_SOURCE_REF:-$COQHAMMER_ROCQ_SOURCE_REF}"
export COQHAMMER_STDLIB_SOURCE_REPO="${COQHAMMER_STDLIB_SOURCE_REPO:-https://github.com/rocq-prover/stdlib.git}"
export COQHAMMER_STDLIB_DEP_NAME="${COQHAMMER_STDLIB_DEP_NAME:-stdlib}"
export COQHAMMER_STDLIB_SOURCE_DIR="${COQHAMMER_STDLIB_SOURCE_DIR:-}"

case ":$PATH:" in
  *":$COQHAMMER_OPAM_SWITCH/_opam/bin:"*) ;;
  *) export PATH="$COQHAMMER_OPAM_SWITCH/_opam/bin:$PATH" ;;
esac

if [ -d "$COQHAMMER_OPAM_SWITCH/_opam" ]; then
  eval "$(opam env --switch="$COQHAMMER_OPAM_SWITCH" --set-switch)"
else
  export OPAMSWITCH="$COQHAMMER_OPAM_SWITCH"
fi
