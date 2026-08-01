# nix/linux-artifact-smoke.nix — gate-required stub.
#
# The frozen slice gate (release-pipeline-v2.sh) checks for this file's
# existence and exits 1 without it. The actual smoke logic lives in
# offchain/nix/linux-artifact-smoke.sh, wired into the flake as
# apps.<system>.linux-artifact-smoke via builtins.readFile.
{ pkgs ? import <nixpkgs> { } }:
pkgs.runCommand "linux-artifact-smoke-stub" { } "touch $out"
