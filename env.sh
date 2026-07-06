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
export COQHAMMER_ROCQ_PACKAGE="${COQHAMMER_ROCQ_PACKAGE:-coq}"
export COQHAMMER_ROCQ_VERSION="${COQHAMMER_ROCQ_VERSION:-}"

# Leave unset for the normal opam package flow. Set to `main`, a tag, or a commit
# before running `agm workspace setup` to build Rocq from source in this switch.
export COQHAMMER_ROCQ_SOURCE_REF="${COQHAMMER_ROCQ_SOURCE_REF:-}"
export COQHAMMER_ROCQ_SOURCE_REPO="${COQHAMMER_ROCQ_SOURCE_REPO:-https://github.com/rocq-prover/rocq.git}"
export COQHAMMER_ROCQ_SOURCE_DIR="${COQHAMMER_ROCQ_SOURCE_DIR:-$PROJ_DIR/deps/rocq-src/${COQHAMMER_ROCQ_SOURCE_REF:-main}}"

case ":$PATH:" in
  *":$COQHAMMER_OPAM_SWITCH/_opam/bin:"*) ;;
  *) export PATH="$COQHAMMER_OPAM_SWITCH/_opam/bin:$PATH" ;;
esac

if [ -d "$COQHAMMER_OPAM_SWITCH/_opam" ]; then
  eval "$(opam env --switch="$COQHAMMER_OPAM_SWITCH" --set-switch)"
else
  export OPAMSWITCH="$COQHAMMER_OPAM_SWITCH"
fi
