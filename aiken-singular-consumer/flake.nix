{
  description = "Pinned Aiken consumer of the published Singular registry package (#477)";

  inputs = {
    # The nixpkgs revision every onchain recipe takes its Aiken compiler from.
    nixpkgs.url = "github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46";
    singular = {
      url = "github:lambdasistemi/singular/d69ab005c3b710aeebf033d3c5cd08c56feb5643";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      singular,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      # The consumer's own sources: manifest, lock and compatibility tests.
      consumer = pkgs.lib.cleanSourceWith {
        src = ./.;
        filter =
          path: _type:
          !(builtins.elem (builtins.baseNameOf path) [
            "build"
            ".git"
            "result"
          ]);
      };
      # The reusable KERI libraries, staged as the consumer's own library so
      # their modules compile in one graph with the Singular package.
      keriLibrary = ../onchain/lib;
      stdlib = pkgs.fetchFromGitHub {
        owner = "aiken-lang";
        repo = "stdlib";
        rev = "v2.2.0";
        hash = "sha256-BDaM+JdswlPasHsI03rLl4OR7u5HsbAd3/VFaoiDTh4=";
      };
      merkle-patricia-forestry = pkgs.fetchFromGitHub {
        owner = "aiken-lang";
        repo = "merkle-patricia-forestry";
        rev = "v2.1.0";
        hash = "sha256-c+ZM1bvR0Zpuz5hCB+F6VWfDThagBHxgoNWHvEUQT/4=";
      };
      checker = pkgs.writeShellApplication {
        name = "aiken-singular-consumer-check";
        runtimeInputs = [
          pkgs.aiken
          pkgs.coreutils
          pkgs.findutils
          pkgs.gawk
          pkgs.gnugrep
          pkgs.gnused
          pkgs.diffutils
          pkgs.jq
          pkgs.util-linux
        ];
        text = ''
          exec bash ${./check.sh} \
            ${consumer} ${keriLibrary} ${singular} ${stdlib} ${merkle-patricia-forestry} \
            ${self.rev or self.dirtyRev or "uncommitted"} \
            ${singular.rev} ${singular.narHash} \
            "$@"
        '';
      };
    in
    {
      packages.${system}.aiken = pkgs.aiken;
      apps.${system}.aiken-singular-consumer = {
        type = "app";
        program = pkgs.lib.getExe checker;
      };
      checks.${system}.aiken-singular-consumer = pkgs.runCommand "aiken-singular-consumer" { } ''
        ${pkgs.lib.getExe checker} "$out"
      '';
    };
}
