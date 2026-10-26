{
  description = "Pinned KERI -> Singular Lean dependency check (#478)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/7f4e8517083e42a1b38907598dadc02c7235b30e";
    singular = {
      url = "github:lambdasistemi/singular/f844a8f423eaf65009c587b9d7dd9ad3e00d21af";
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
      source = pkgs.lib.cleanSourceWith {
        src = self;
        filter =
          path: _type:
          !(builtins.elem (builtins.baseNameOf path) [
            ".lake"
            ".git"
            "result"
          ]);
      };
      # Lake verifies its Git manifest against the package's Git metadata.
      # Keep real commit/tree objects, but not the variable pack layout.
      singularCheckout = pkgs.fetchgit {
        url = "https://github.com/lambdasistemi/singular.git";
        rev = singular.rev;
        hash = "sha256-ryr4YWYNCG1zahf+qSFVpwHddP6pKQyB43PBkiv8Afs=";
        leaveDotGit = true;
        postFetch = ''
          # Hide packs while unpacking so Git writes every object as a loose object.
          pack_dir=$(mktemp -d)
          mv "$out"/.git/objects/pack/* "$pack_dir"/
          for pack in "$pack_dir"/*.pack; do
            git -C "$out" -c core.compression=9 unpack-objects < "$pack"
          done
          rm -rf "$pack_dir"
          # Remove the advertisement for the packs that no longer exist.
          rm -f "$out/.git/objects/info/packs"
          git -C "$out" fsck --strict
        '';
      };
      checker = pkgs.writeShellApplication {
        name = "singular-dependency-check";
        runtimeInputs = [
          pkgs.lean4
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnugrep
          pkgs.gnused
          pkgs.diffutils
          pkgs.jq
          pkgs.git
        ];
        text = ''
          export SINGULAR_CHECKOUT_HASH=${pkgs.lib.escapeShellArg singularCheckout.outputHash}
          exec bash ${./check-singular-dependency.sh} \
            ${source} ${singularCheckout} \
            ${self.rev or self.dirtyRev or "uncommitted"} \
            ${singular.rev} ${singular.narHash} \
            "$@"
        '';
      };
    in
    {
      packages.${system}.lean = pkgs.lean4;
      apps.${system}.singular-dependency = {
        type = "app";
        program = pkgs.lib.getExe checker;
      };
      checks.${system}.singular-dependency = pkgs.runCommand "singular-dependency" { } ''
        ${pkgs.lib.getExe checker} "$out"
      '';
    };
}
