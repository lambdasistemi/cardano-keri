{
  description = "cardano-keri Haskell library (Ed25519 + CESR, wasm-portable)";
  nixConfig = {
    extra-substituters = [ "https://cache.iog.io" ];
    extra-trusted-public-keys =
      [ "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" ];
  };
  inputs = {
    haskellNix.url =
      "github:input-output-hk/haskell.nix/8b447d7f57d62fab9249f79bb916bc891e29b9d0";
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    iohkNix = {
      url = "github:input-output-hk/iohk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    CHaP = {
      url = "github:intersectmbo/cardano-haskell-packages?ref=repo";
      flake = false;
    };
  };

  outputs =
    inputs@{ self, nixpkgs, flake-parts, haskellNix, iohkNix, CHaP, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      perSystem = { system, ... }:
        let
          pkgs = import nixpkgs {
            overlays = [
              iohkNix.overlays.crypto
              haskellNix.overlay
              iohkNix.overlays.haskell-nix-crypto
            ];
            inherit system;
          };

          # Tooling is pinned to the cabal.project hackage index-state so the
          # fourmolu/hlint versions used by `format` and `format-check` agree.
          indexState = "2026-04-17T00:00:00Z";
          toolArgs = name:
            {
              index-state = indexState;
            } // pkgs.lib.optionalAttrs (name == "cabal-fmt") {
              cabalProjectLocal = ''
                allow-newer: cabal-fmt:base
              '';
            };
          tool = name: pkgs.haskell-nix.tool "ghc9123" name (toolArgs name);

          fix-libs = { lib, pkgs, ... }: {
            packages.cardano-crypto-class.components.library.pkgconfig =
              lib.mkForce [[ pkgs.libsodium-vrf pkgs.secp256k1 pkgs.libblst ]];
          };

          project = pkgs.haskell-nix.cabalProject' {
            name = "cardano-keri";
            src = ./.;
            compiler-nix-name = "ghc9123";
            modules = [ fix-libs ];
            inputMap = { "https://chap.intersectmbo.org/" = CHaP; };
            shell = {
              tools = {
                cabal = toolArgs "cabal";
                fourmolu = toolArgs "fourmolu";
                hlint = toolArgs "hlint";
                cabal-fmt = toolArgs "cabal-fmt";
              };
              withHoogle = false;
              buildInputs = [ pkgs.just pkgs.nixfmt-classic ];
            };
          };

          unit-tests-exe =
            project.hsPkgs.cardano-keri.components.tests.unit-tests;

          # writeShellApplication gives each runner a strict PATH — every
          # binary it calls must be listed in runtimeInputs.
          format-runner = pkgs.writeShellApplication {
            name = "format";
            runtimeInputs = [
              (tool "fourmolu")
              (tool "cabal-fmt")
              pkgs.findutils
              pkgs.nixfmt-classic
            ];
            text = ''
              mapfile -d "" hs_files < <(find . -name '*.hs' -not -path './dist-newstyle/*' -not -path './.direnv/*' -print0)
              for _ in 1 2 3; do
                fourmolu -i "''${hs_files[@]}"
              done
              find . -name '*.cabal' -not -path './dist-newstyle/*' -print0 | xargs -0 cabal-fmt -i
              find . -name '*.nix' -not -path './dist-newstyle/*' -print0 | xargs -0 nixfmt
            '';
          };
          format-check-runner = pkgs.writeShellApplication {
            name = "format-check";
            runtimeInputs =
              [ (tool "fourmolu") (tool "cabal-fmt") pkgs.findutils ];
            text = ''
              mapfile -d "" hs_files < <(find . -name '*.hs' -not -path './dist-newstyle/*' -not -path './.direnv/*' -print0)
              fourmolu -m check "''${hs_files[@]}"
              find . -name '*.cabal' -not -path './dist-newstyle/*' -print0 | xargs -0 cabal-fmt -c
            '';
          };
          hlint-runner = pkgs.writeShellApplication {
            name = "hlint";
            runtimeInputs = [ (tool "hlint") pkgs.findutils ];
            text = ''
              find . -name '*.hs' -not -path './dist-newstyle/*' -not -path './.direnv/*' -print0 | xargs -0 hlint
            '';
          };
          # Runs the compiled test binary — the false-green fix. `nix build`
          # on the raw test component only compiles it; this executes it.
          unit-tests-runner = pkgs.writeShellApplication {
            name = "unit-tests";
            text = ''
              exec ${unit-tests-exe}/bin/unit-tests "$@"
            '';
          };
          # Sandbox check that INVOKES the runner, so `nix flake check` runs
          # the tests too (not just compiles them).
          unit-tests-check = pkgs.runCommand "unit-tests-check" { } ''
            ${unit-tests-runner}/bin/unit-tests
            touch $out
          '';

        in {
          packages = {
            unit-tests = unit-tests-exe;
            format = format-runner;
            format-check = format-check-runner;
            hlint = hlint-runner;
          };
          checks.unit-tests = unit-tests-check;
          apps = {
            format = {
              type = "app";
              program = "${format-runner}/bin/format";
            };
            format-check = {
              type = "app";
              program = "${format-check-runner}/bin/format-check";
            };
            hlint = {
              type = "app";
              program = "${hlint-runner}/bin/hlint";
            };
            unit-tests = {
              type = "app";
              program = "${unit-tests-runner}/bin/unit-tests";
            };
          };
          devShells.default = project.shell;
        };
    };
}
