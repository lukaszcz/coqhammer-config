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

switch="${COQHAMMER_OPAM_SWITCH:-$REPO_DIR}"
ocaml_package="${COQHAMMER_OCAML:-ocaml-base-compiler.5.3.0}"
rocq_package="${COQHAMMER_ROCQ_PACKAGE:-coq}"
rocq_version="${COQHAMMER_ROCQ_VERSION:-}"
rocq_source_ref="${COQHAMMER_ROCQ_SOURCE_REF:-}"
rocq_source_repo="${COQHAMMER_ROCQ_SOURCE_REPO:-https://github.com/rocq-prover/rocq.git}"
rocq_dep_name="${COQHAMMER_ROCQ_DEP_NAME:-rocq}"
rocq_source_dir="${COQHAMMER_ROCQ_SOURCE_DIR:-}"

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
  local checkout="$1"
  local path=""

  path="$(agm dep list --verbose --all | awk -v target="$rocq_dep_name/$checkout" '$1 == target { print $NF; found = 1 } END { exit found ? 0 : 1 }')" || true
  if [ -n "$path" ]; then
    printf '%s\n' "$path"
    return 0
  fi

  return 1
}

agm_dep_exists() {
  agm dep list --all | awk -v prefix="$rocq_dep_name/" 'index($1, prefix) == 1 { found = 1 } END { exit found ? 0 : 1 }'
}

checkout_rocq_source() {
  if [ -n "$rocq_source_dir" ]; then
    case "$rocq_source_dir" in
      "$PROJ_DIR/deps"|"$PROJ_DIR/deps"/*)
        echo "COQHAMMER_ROCQ_SOURCE_DIR must not point under $PROJ_DIR/deps; unset it and let agm dep manage the checkout" >&2
        exit 1
        ;;
    esac

    if [ ! -e "$rocq_source_dir/.git" ]; then
      echo "COQHAMMER_ROCQ_SOURCE_DIR must point to an existing git checkout: $rocq_source_dir" >&2
      exit 1
    fi

    git -C "$rocq_source_dir" fetch --tags origin
    git -C "$rocq_source_dir" checkout "$rocq_source_ref"
    return
  fi

  if ! rocq_source_dir="$(agm_dep_checkout_path "$rocq_source_ref")"; then
    if agm_dep_exists; then
      agm dep switch "$rocq_dep_name" "$rocq_source_ref" || agm dep switch --branch "$rocq_dep_name" "$rocq_source_ref"
    else
      agm dep new --branch "$rocq_source_ref" "$rocq_source_repo"
    fi

    if ! rocq_source_dir="$(agm_dep_checkout_path "$rocq_source_ref")"; then
      echo "agm dep did not report a checkout path for $rocq_dep_name/$rocq_source_ref" >&2
      exit 1
    fi
  fi
}

install_source_rocq() {
  echo "Building Rocq from source ref '$rocq_source_ref' in $switch"
  checkout_rocq_source

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

ensure_switch

if [ -n "$rocq_source_ref" ]; then
  install_source_rocq
else
  install_opam_rocq
fi

echo "Workspace setup complete. Active switch: $switch"
