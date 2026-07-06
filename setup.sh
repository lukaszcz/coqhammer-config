#!/usr/bin/env bash
set -euo pipefail

# Initialize a CoqHammer workspace-local opam switch.
#
# Configuration knobs:
#   COQHAMMER_OPAM_SWITCH        default: $REPO_DIR, prefix: $REPO_DIR/_opam
#   COQHAMMER_OCAML              default: ocaml-base-compiler.5.3.0
#   COQHAMMER_ROCQ_PACKAGE       default: coq
#   COQHAMMER_ROCQ_VERSION       unset to use opam file constraints; set to force an opam version
#   COQHAMMER_ROCQ_SOURCE_REF    unset for opam package; set to an AGM-managed branch/tag for source build
#   COQHAMMER_ROCQ_SOURCE_REPO   default: https://github.com/rocq-prover/rocq.git
#   COQHAMMER_ROCQ_DEP_NAME      default: rocq, AGM dependency name under $PROJ_DIR/deps
#   COQHAMMER_ROCQ_SOURCE_DIR    unset to use agm dep; set to an existing local checkout override
#
# Since Rocq 9.0 the standard library lives in its own repository and must be
# built separately when Rocq is built from source. These knobs control it and
# only take effect when COQHAMMER_ROCQ_SOURCE_REF is set:
#   COQHAMMER_STDLIB_SOURCE_REF  default: $COQHAMMER_ROCQ_SOURCE_REF; matching stdlib branch/tag
#   COQHAMMER_STDLIB_SOURCE_REPO default: https://github.com/rocq-prover/stdlib.git
#   COQHAMMER_STDLIB_DEP_NAME    default: stdlib, AGM dependency name under $PROJ_DIR/deps
#   COQHAMMER_STDLIB_SOURCE_DIR  unset to use agm dep; set to an existing local checkout override

switch="${COQHAMMER_OPAM_SWITCH:-$REPO_DIR}"
ocaml_package="${COQHAMMER_OCAML:-ocaml-base-compiler.5.3.0}"
rocq_package="${COQHAMMER_ROCQ_PACKAGE:-coq}"
rocq_version="${COQHAMMER_ROCQ_VERSION:-}"
rocq_source_ref="${COQHAMMER_ROCQ_SOURCE_REF:-}"
rocq_source_repo="${COQHAMMER_ROCQ_SOURCE_REPO:-https://github.com/rocq-prover/rocq.git}"
rocq_dep_name="${COQHAMMER_ROCQ_DEP_NAME:-rocq}"
rocq_source_dir="${COQHAMMER_ROCQ_SOURCE_DIR:-}"
stdlib_source_ref="${COQHAMMER_STDLIB_SOURCE_REF:-$rocq_source_ref}"
stdlib_source_repo="${COQHAMMER_STDLIB_SOURCE_REPO:-https://github.com/rocq-prover/stdlib.git}"
stdlib_dep_name="${COQHAMMER_STDLIB_DEP_NAME:-stdlib}"
stdlib_source_dir="${COQHAMMER_STDLIB_SOURCE_DIR:-}"

ensure_switch() {
  if [ ! -d "$switch/_opam" ]; then
    echo "Creating workspace opam switch: $switch"
    opam switch create "$switch" "$ocaml_package" --no-install --yes
  fi

  eval "$(opam env --switch="$switch" --set-switch)"
  opam update --yes
}

install_opam_rocq() {
  if [ -n "$rocq_version" ]; then
    echo "Installing Rocq/Coq from opam into $switch: $rocq_package.$rocq_version"
    opam install --yes "$rocq_package.$rocq_version"
    opam install --yes --deps-only \
      --ignore-constraints-on=coq,coq-core,coq-stdlib,coqide-server,rocq-runtime,rocq-core,rocq-stdlib \
      ./coq-hammer-tactics.opam ./coq-hammer.opam
  else
    echo "Installing Rocq/Coq from opam into $switch using workspace opam constraints"
    opam install --yes --deps-only ./coq-hammer-tactics.opam ./coq-hammer.opam
  fi
}

agm_dep_checkout_path() {
  local dep_name="$1"
  local checkout="$2"
  local path=""

  path="$(agm dep list --verbose --all | awk -v target="$dep_name/$checkout" '$1 == target { print $NF; found = 1 } END { exit found ? 0 : 1 }')" || true
  if [ -n "$path" ]; then
    printf '%s\n' "$path"
    return 0
  fi

  return 1
}

agm_dep_exists() {
  local dep_name="$1"
  agm dep list --all | awk -v prefix="$dep_name/" 'index($1, prefix) == 1 { found = 1 } END { exit found ? 0 : 1 }'
}

# Resolve a source checkout for an AGM dependency, printing its path on stdout.
# All informational output is sent to stderr so the path can be captured with
# command substitution.
#   checkout_source <dep_name> <ref> <repo> <source_dir_override>
checkout_source() {
  local dep_name="$1"
  local ref="$2"
  local repo="$3"
  local source_dir="$4"
  local dir=""

  if [ -n "$source_dir" ]; then
    case "$source_dir" in
      "$PROJ_DIR/deps"|"$PROJ_DIR/deps"/*)
        echo "source dir override must not point under $PROJ_DIR/deps; unset it and let agm dep manage the checkout" >&2
        exit 1
        ;;
    esac

    if [ ! -e "$source_dir/.git" ]; then
      echo "source dir override must point to an existing git checkout: $source_dir" >&2
      exit 1
    fi

    git -C "$source_dir" fetch --tags origin >&2
    git -C "$source_dir" checkout "$ref" >&2
    printf '%s\n' "$source_dir"
    return
  fi

  if ! dir="$(agm_dep_checkout_path "$dep_name" "$ref")"; then
    if agm_dep_exists "$dep_name"; then
      { agm dep switch "$dep_name" "$ref" || agm dep switch --branch "$dep_name" "$ref"; } >&2
    else
      agm dep new --branch "$ref" "$repo" >&2
    fi

    if ! dir="$(agm_dep_checkout_path "$dep_name" "$ref")"; then
      echo "agm dep did not report a checkout path for $dep_name/$ref" >&2
      exit 1
    fi
  fi

  printf '%s\n' "$dir"
}

install_source_rocq() {
  echo "Building Rocq from source ref '$rocq_source_ref' in $switch"
  if ! rocq_source_dir="$(checkout_source "$rocq_dep_name" "$rocq_source_ref" "$rocq_source_repo" "$rocq_source_dir")"; then
    exit 1
  fi

  opam install --yes conf-g++ || opam install --yes conf-clang

  (
    cd "$rocq_source_dir"
    source_packages=()
    source_opams=()
    for package in rocq-runtime rocq-core rocq-stdlib coq-core coq-stdlib coq; do
      if [ -f "$package.opam" ]; then
        source_packages+=("$package")
        source_opams+=("./$package.opam")
      fi
    done

    if [ "${#source_packages[@]}" -eq 0 ]; then
      echo "No supported Rocq/Coq opam files found in $rocq_source_dir" >&2
      exit 1
    fi

    opam install --yes --deps-only "${source_opams[@]}"
    make dunestrap
    package_csv="$(IFS=,; echo "${source_packages[*]}")"
    dune build -p "$package_csv"
    dune install "${source_packages[@]}"
  )
}

install_source_stdlib() {
  # Since Rocq 9.0 the standard library ships in its own repository, so a
  # source build of Rocq does not include it. Build and install it separately
  # against the just-installed Rocq, otherwise the switch is left without the
  # `Stdlib` library that CoqHammer requires.
  echo "Building Rocq standard library from source ref '$stdlib_source_ref' in $switch"
  local stdlib_dir=""
  if ! stdlib_dir="$(checkout_source "$stdlib_dep_name" "$stdlib_source_ref" "$stdlib_source_repo" "$stdlib_source_dir")"; then
    exit 1
  fi

  (
    cd "$stdlib_dir"
    if [ ! -f rocq-stdlib.opam ]; then
      echo "No rocq-stdlib.opam found in $stdlib_dir" >&2
      exit 1
    fi
    # rocq_makefile honours these variables from the environment, so an inherited
    # value (e.g. ROCQ pointing at a Rocq source checkout) would be used instead
    # of the `rocq` we just installed. Clear them so the build resolves `rocq`
    # from PATH, which the switch has set to this switch's binaries.
    unset ROCQ ROCQBIN ROCQMAKEFILE COQBIN COQC COQDEP COQLIB ROCQLIB
    # The stdlib builds with rocq_makefile against the installed `rocq`; this
    # mirrors rocq-stdlib.opam's own build/install commands.
    make -j"$(nproc)"
    make install
  )
}

ensure_switch

if [ -n "$rocq_source_ref" ]; then
  install_source_rocq
  install_source_stdlib
else
  install_opam_rocq
fi

echo "Workspace setup complete. Active switch: $switch"
