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
    # Tracked onchain sources for the flake-owned Aiken blueprint derivation.
    # Resolved via the repo git tree (gitignore-respecting); the blueprint
    # derivation additionally filters it through cleanSourceWith so its source
    # is tracked Aiken sources only — no build/ or plutus.json (NOTE-014/016).
    onchain = {
      url = "path:../onchain";
      flake = false;
    };
    # cardano-node 10.7.0 provides the node binary the withDevnet e2e smoke
    # spawns (runtime input only — never a Cabal source-repository-package).
    cardano-node.url = "github:IntersectMBO/cardano-node/10.7.0";
    # Pinned cardano-node-clients (owns the `devnet` sublibrary): the source
    # supplies E2E_GENESIS_DIR; the rev matches the cabal.project pin.
    cardano-node-clients = {
      url =
        "github:lambdasistemi/cardano-node-clients/ca86f11d27b34e37d3814e4d3c3d66e256400403";
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

          # pkg-config native-lib overrides for the cardano-node-clients
          # closure (proven set copied from cardano-tx-tools). Without these
          # the dev shell / haskell.nix build cannot resolve lmdb, the VRF
          # sodium fork, or (on Linux) liburing for the io_uring block layer.
          fix-libs = { lib, pkgs, ... }:
            {
              packages.cardano-crypto-praos.components.library.pkgconfig =
                lib.mkForce [ [ pkgs.libsodium-vrf ] ];
              packages.cardano-crypto-class.components.library.pkgconfig =
                lib.mkForce [[
                  pkgs.libsodium-vrf
                  pkgs.secp256k1
                  pkgs.libblst
                ]];
              packages.cardano-lmdb.components.library.pkgconfig =
                lib.mkForce [ [ pkgs.lmdb ] ];
            } // lib.optionalAttrs
            (lib.elem system [ "x86_64-linux" "aarch64-linux" ]) {
              # liburing is Linux-only; gate on the outer `system` so the
              # override never references blockio-uring on Darwin.
              packages.blockio-uring.components.library.pkgconfig =
                lib.mkForce [ [ pkgs.liburing ] ];
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
              # lmdb + liburing + pkg-config so `cabal build` in the shell can
              # resolve the cardano-node-clients closure's native libs. liburing
              # is Linux-only — gate it on the declared systems so the shell
              # still evaluates on aarch64-darwin.
              buildInputs =
                [ pkgs.just pkgs.nixfmt-classic pkgs.lmdb pkgs.pkg-config ]
                ++ pkgs.lib.optionals
                (pkgs.lib.elem system [ "x86_64-linux" "aarch64-linux" ])
                [ pkgs.liburing ];
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

          # Live-boundary withDevnet e2e wiring. Linux-only (the smoke spawns a
          # real cardano-node); the whole attrset is empty on Darwin so its
          # node/blueprint references are never forced there.
          e2eWiring = pkgs.lib.optionalAttrs (system == "x86_64-linux") (let
            # Flake-owned Aiken blueprint: build plutus.json from the TRACKED
            # onchain sources + aiken.lock in a fixed-output derivation (aiken
            # fetches its locked deps over the network), yielding an immutable
            # /nix/store blueprint the e2e smoke consumes instead of the
            # gitignored worktree plutus.json (NOTE-016).
            # Filtered onchain source: the `onchain` input already resolves
            # via the repo git tree (so gitignored build/ + plutus.json are
            # absent), but we ALSO filter explicitly so the blueprint's
            # source provenance is tracked-Aiken-sources-only regardless of
            # how the input is materialized (NOTE-014/016): keep aiken.toml,
            # aiken.lock and the *.ak trees; drop build/ and plutus.json.
            onchainSrc = pkgs.lib.cleanSourceWith {
              name = "keri-onchain-src";
              src = inputs.onchain;
              filter = path: _type:
                let
                  rel = pkgs.lib.removePrefix (toString inputs.onchain + "/")
                    (toString path);
                  top = pkgs.lib.head (pkgs.lib.splitString "/" rel);
                in top != "build" && rel != "plutus.json";
            };
            blueprint = pkgs.stdenvNoCC.mkDerivation {
              name = "keri-cage-plutus-blueprint";
              dontUnpack = true;
              nativeBuildInputs = [ pkgs.aiken pkgs.cacert ];
              outputHashMode = "flat";
              outputHashAlgo = "sha256";
              outputHash =
                "sha256-ecf9hks1cunhAC2fDbk1cK3EVOUu20PQ+0D4JeuYDCM=";
              buildPhase = ''
                export HOME="$TMPDIR"
                export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
                cp -rL ${onchainSrc}/. ./work
                chmod -R +w ./work
                cd ./work
                rm -rf build plutus.json
                aiken build
              '';
              installPhase = ''
                cp plutus.json "$out"
              '';
            };
            cardanoNode = inputs.cardano-node.packages.${system}.cardano-node;
            e2eExe = project.hsPkgs.cardano-keri.components.tests.e2e-tests;
            # One strict-PATH app exposed twice (apps.e2e via nix run +
            # checks.e2e via a runCommand that invokes it), modeled on
            # cardano-tx-tools/nix/checks.nix. E2E_GENESIS_DIR comes from the
            # pinned cardano-node-clients source; KERI_CAGE_BLUEPRINT from the
            # flake-owned blueprint above.
            runner = pkgs.writeShellApplication {
              name = "e2e";
              # Strict PATH: the E2E executable AND the node binary it spawns
              # must both be listed so the app is self-contained.
              runtimeInputs = [ e2eExe cardanoNode pkgs.coreutils pkgs.which ];
              text = ''
                export E2E_GENESIS_DIR="${inputs.cardano-node-clients}/e2e-test/genesis"
                export KERI_CAGE_BLUEPRINT="${blueprint}"
                exec e2e-tests "$@"
              '';
            };
            check = pkgs.runCommand "e2e-check" { } ''
              ${pkgs.lib.getExe runner}
              touch "$out"
            '';
          in { inherit blueprint runner check; });

        in {
          packages = {
            unit-tests = unit-tests-exe;
            format = format-runner;
            format-check = format-check-runner;
            hlint = hlint-runner;
          } // pkgs.lib.optionalAttrs (e2eWiring ? runner) {
            e2e = e2eWiring.runner;
            plutus-blueprint = e2eWiring.blueprint;
          };
          checks = {
            unit-tests = unit-tests-check;
          } // pkgs.lib.optionalAttrs (e2eWiring ? check) {
            e2e = e2eWiring.check;
          };
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
          } // pkgs.lib.optionalAttrs (e2eWiring ? runner) {
            e2e = {
              type = "app";
              program = "${e2eWiring.runner}/bin/e2e";
            };
          };
          devShells.default = project.shell;
        };
    };
}
