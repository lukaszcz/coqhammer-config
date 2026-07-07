#!/usr/bin/env bash
set -euo pipefail

# Initialize a CoqHammer workspace-local opam switch.
#
# Configuration knobs:
#   COQHAMMER_OPAM_SWITCH        default: $REPO_DIR, prefix: $REPO_DIR/_opam
#   COQHAMMER_OCAML              default: ocaml-base-compiler.5.3.0
#   COQHAMMER_ROCQ_PACKAGES      space-separated opam packages (each an optional
#                                "pkg" or "pkg.version") to install explicitly
#                                before resolving CoqHammer's remaining deps while
#                                ignoring the Rocq version constraints in the opam
#                                files. Use this to pin Rocq when the exact version
#                                is not yet resolvable from the constraints alone
#                                (e.g. rocq-core is on opam but rocq-stdlib is not
#                                yet published for the same X.Y). Default: unset,
#                                in which case the opam-file constraints are solved
#                                directly. Since the Rocq rename (Rocq >= 9.0) the
#                                relevant packages are rocq-core / rocq-stdlib; the
#                                deprecated meta-package "coq" is used only for the
#                                older Coq (< 9.0) branches.
#   COQHAMMER_ROCQ_PACKAGE       legacy single-package name for the pin path below;
#                                default: version-aware (rocq-core for Rocq >= 9.0,
#                                otherwise coq). Prefer COQHAMMER_ROCQ_PACKAGES.
#   COQHAMMER_ROCQ_VERSION       unset to use opam file constraints; set to force an
#                                opam version of COQHAMMER_ROCQ_PACKAGE (legacy pin).
#   COQHAMMER_ROCQ_SOURCE_REF    unset for opam package; set to an AGM-managed branch/tag for source build
#   COQHAMMER_ROCQ_SOURCE_REPO   default: https://github.com/rocq-prover/rocq.git
#   COQHAMMER_ROCQ_DEP_NAME      default: rocq, AGM dependency name under $PROJ_DIR/deps
#   COQHAMMER_ROCQ_SOURCE_DIR    unset to use agm dep; set to an existing local checkout override
#   COQHAMMER_DUNE_VERSION       unset to auto-select; set to force an opam dune version for
#                                the source build (see ensure_build_dune below)
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
rocq_packages="${COQHAMMER_ROCQ_PACKAGES:-}"
rocq_package="${COQHAMMER_ROCQ_PACKAGE:-}"
rocq_version="${COQHAMMER_ROCQ_VERSION:-}"
rocq_source_ref="${COQHAMMER_ROCQ_SOURCE_REF:-}"
rocq_source_repo="${COQHAMMER_ROCQ_SOURCE_REPO:-https://github.com/rocq-prover/rocq.git}"
rocq_dep_name="${COQHAMMER_ROCQ_DEP_NAME:-rocq}"
rocq_source_dir="${COQHAMMER_ROCQ_SOURCE_DIR:-}"
stdlib_source_ref="${COQHAMMER_STDLIB_SOURCE_REF:-$rocq_source_ref}"
stdlib_source_repo="${COQHAMMER_STDLIB_SOURCE_REPO:-https://github.com/rocq-prover/stdlib.git}"
stdlib_dep_name="${COQHAMMER_STDLIB_DEP_NAME:-stdlib}"
stdlib_source_dir="${COQHAMMER_STDLIB_SOURCE_DIR:-}"
dune_version="${COQHAMMER_DUNE_VERSION:-}"

# Newest dune that still ships the legacy `coq` build language; dune 3.24
# deleted it in favour of the `rocq` language.
dune_last_coq_lang="3.23.1"

# AGM injects env vars for declared deps (e.g. ROCQ=$PROJ_DIR/deps/rocq/master
# for a `rocq` dep). opam and rocq_makefile both honour these: rocq_makefile
# uses $ROCQ as the compiler binary, so an inherited value pointing at a Rocq
# source *directory* makes every stdlib .vo rule fail with "Permission denied"
# (exit 126). Clear them globally before any opam operation so they can never
# leak into an opam build; source builds below resolve Rocq from `agm dep`
# checkout paths and PATH, not from these variables.
unset ROCQ ROCQBIN ROCQMAKEFILE ROCQLIB COQBIN COQC COQDEP COQLIB

ensure_switch() {
  if [ ! -d "$switch/_opam" ]; then
    echo "Creating workspace opam switch: $switch"
    opam switch create "$switch" "$ocaml_package" --no-install --yes
  fi

  eval "$(opam env --switch="$switch" --set-switch)"
  opam update --yes
}

# branch_rocq_version: the Rocq X.Y this branch targets, read from the Rocq
# dependency constraint in coq-hammer.opam (e.g. "9.2" from
# '"rocq-core" {>= "9.2" & < "9.3~"}', or from the legacy '"coq" {>= ...}').
branch_rocq_version() {
  sed -n -E \
    's/^[[:space:]]*"(rocq-core|coq)"[[:space:]]*\{>= "([0-9]+\.[0-9]+).*/\2/p' \
    coq-hammer.opam | head -n1
}

# default_rocq_package: the opam meta/core package name for this branch's Rocq.
# Since the Rocq rename (Rocq >= 9.0) it is rocq-core; the "coq" package is the
# deprecated shim kept only for the older Coq (< 9.0) branches.
default_rocq_package() {
  local v maj
  v="$(branch_rocq_version)"
  maj="${v%%.*}"
  if [ -n "$maj" ] && [ "$maj" -ge 9 ] 2>/dev/null; then
    echo "rocq-core"
  else
    echo "coq"
  fi
}

install_opam_rocq() {
  # Packages to install explicitly before resolving the remaining CoqHammer
  # dependencies. COQHAMMER_ROCQ_PACKAGES (a list) takes precedence; otherwise
  # the legacy single-package pin (COQHAMMER_ROCQ_PACKAGE.COQHAMMER_ROCQ_VERSION)
  # is used when a version is forced. Empty means "let the opam-file constraints
  # solve on their own".
  local pkgs=""
  if [ -n "$rocq_packages" ]; then
    pkgs="$rocq_packages"
  elif [ -n "$rocq_version" ]; then
    pkgs="${rocq_package:-$(default_rocq_package)}.$rocq_version"
  fi

  if [ -n "$pkgs" ]; then
    echo "Installing Rocq from opam into $switch: $pkgs"
    # shellcheck disable=SC2086  # word splitting is intentional: $pkgs is a list
    opam install --yes $pkgs
    opam install --yes --deps-only \
      --ignore-constraints-on=coq,coq-core,coq-stdlib,coqide-server,rocq-runtime,rocq-core,rocq-stdlib \
      ./coq-hammer-tactics.opam ./coq-hammer.opam
  else
    echo "Installing Rocq from opam into $switch using workspace opam constraints"
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

# Ensure the switch has a dune that can build the given Rocq source tree.
#
# Rocq's opam files only constrain `dune {>= "3.8"}`, so opam otherwise pulls in
# the newest dune available. That breaks source builds of every Rocq release up
# to 9.2, whose dune-project declares the legacy `(using coq ...)` build
# language that dune 3.24 deleted ("Extension coq was deleted in the 3.24
# version of the dune language"). Such trees need a dune < 3.24, where the `coq`
# extension still exists (through 3.23). Newer Rocq (10.x / master) migrated to
# the `(using rocq ...)` language and builds fine with the latest dune, so only
# pin when the source actually uses the legacy language. dune 3.23 also provides
# the `rocq 0.11` language CoqHammer's own dune files use (available since dune
# 3.21), so a single pinned dune serves both the Rocq and CoqHammer builds.
#
# COQHAMMER_DUNE_VERSION overrides the auto-selection for either case.
ensure_build_dune() {
  local source_dir="$1"
  local requested="$dune_version"

  if [ -z "$requested" ] && grep -q '^(using coq ' "$source_dir/dune-project" 2>/dev/null; then
    echo "Rocq source uses the legacy dune 'coq' build language; pinning a compatible dune"
    requested="$dune_last_coq_lang"
  fi

  if [ -n "$requested" ]; then
    echo "Installing dune.$requested into $switch"
    opam install --yes "dune.$requested"
  fi
}

install_source_rocq() {
  echo "Building Rocq from source ref '$rocq_source_ref' in $switch"
  if ! rocq_source_dir="$(checkout_source "$rocq_dep_name" "$rocq_source_ref" "$rocq_source_repo" "$rocq_source_dir")"; then
    exit 1
  fi

  ensure_build_dune "$rocq_source_dir"

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
    # The Rocq/Coq env-var pointers were cleared globally at the top of this
    # script, so rocq_makefile resolves `rocq` from PATH (this switch's bin).
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
