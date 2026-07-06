#!/usr/bin/env bash
#
# Workspace config for the rocq-9.2 development branch (Rocq 9.2).
#
# Rocq 9.2 is not available as an opam package, so build it (and, since Rocq 9.0,
# the standard library) from source. See $PROJ_DIR/config/README.md.

export COQHAMMER_ROCQ_SOURCE_REF=V9.2.0
# NOTE: no matching stdlib ref was found on the stdlib repository; the Rocq ref
# is used as a best guess. If the source build fails to find the standard
# library, set COQHAMMER_STDLIB_SOURCE_REF to the correct stdlib branch/tag.
export COQHAMMER_STDLIB_SOURCE_REF=V9.2.0
