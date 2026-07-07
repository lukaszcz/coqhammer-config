#!/usr/bin/env bash
#
# Workspace config for the rocq-9.2 development branch (Rocq 9.2).
#
# Rocq 9.2 is available on opam as rocq-core.9.2.0, but the standard library
# has not yet been published for 9.2 -- the newest rocq-stdlib on opam is
# 9.1.0, which builds and loads correctly against the 9.2 core. So install the
# core at 9.2 and the stdlib at the newest available version explicitly;
# setup.sh then resolves CoqHammer's remaining dependencies while ignoring the
# Rocq version constraints in the opam files (which ask for rocq-stdlib >= 9.2).
#
# Once rocq-stdlib 9.2 is published on opam, drop this override entirely: the
# opam-file constraints in coq-hammer*.opam will then solve on their own.
export COQHAMMER_ROCQ_PACKAGES="rocq-core.9.2.0 rocq-stdlib.9.1.0"
