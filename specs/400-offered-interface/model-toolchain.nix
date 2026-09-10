# Conformance uses this repository's Lean version, independently of Blaster.
{ system ? builtins.currentSystem }:
let
  project = builtins.getFlake (toString ../../offchain);
  pkgs = import project.inputs.leanNixpkgs {
    inherit system;
    overlays = [
      (project.inputs.lean4Nix.readToolchainFile {
        toolchain = ../../lean/lean-toolchain;
        binary = true;
      })
    ];
  };
in
pkgs.lean.lean-all
