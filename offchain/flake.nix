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
    # #176 Slice 1: the canonical OpenAPI contract lives at the repo-root
    # docs/assets/swagger/ (read by mkdocs and this flake's SwaggerDriftSpec
    # alike) but this flake's own `src` is necessarily scoped to offchain/,
    # same reasoning as the `onchain` input above. Sourced as its own flake
    # input rather than a second tracked copy under offchain/.
    docsSwagger = {
      url = "path:../docs/assets/swagger";
      flake = false;
    };
    # #219 A4 follow-up: ManifestSpec.hs's board-manifest-integrity check
    # (added restructuring the live board-policy assertion into a
    # manifest-integrity check, per A-009) reads the committed
    # deploy/preprod/board-manifest.json — repo-root, outside offchain/'s
    # own `src`, same reasoning as `onchain`/`docsSwagger` above. Sourced as
    # its own flake input and passed via an env var (mirrors how `blueprint`
    # itself reaches deploymentTestsRunner) rather than a symlink, which
    # cannot survive haskell.nix re-rooting `src` into its own store copy.
    deployPreprod = {
      url = "path:../deploy/preprod";
      flake = false;
    };
    # cardano-node 10.7.0 provides the node binary the withDevnet e2e smoke
    # spawns (runtime input only — never a Cabal source-repository-package).
    cardano-node.url = "github:IntersectMBO/cardano-node/10.7.0";
    # Pinned cardano-node-clients (owns the `devnet` sublibrary): the source
    # supplies E2E_GENESIS_DIR; the rev matches the cabal.project pin.
    cardano-node-clients = {
      url =
        "github:lambdasistemi/cardano-node-clients/a10cdb73317a2b6d5375b216f72f40b71736e648";
      flake = false;
    };
    # NixOS/bundlers provides toAppImage, toDEB, toRPM for Linux release
    # artifacts. Follows our nixpkgs so the bundlers share the same store.
    bundlers = {
      url = "github:NixOS/bundlers";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The compiled-UPLC tractability toolchain is acceptance-critical. Direct
    # sources name immutable revisions; their transitive inputs are bound by
    # flake.lock and audited by the runnable `blaster` surface.
    leanBlaster.url =
      "github:paolino/Lean-blaster/62d2d59abda37e90097e655b40e27545bba16f3c";
    lean4Nix.follows = "leanBlaster/lean4-nix";
    leanNixpkgs.follows = "leanBlaster/nixpkgs";
    plutusCoreBlaster = {
      url =
        "github:input-output-hk/PlutusCoreBlaster/7cf5a78c54b9694ef093bf49edb5d3799b2a49c9";
      flake = false;
    };
    cardanoLedgerApiBlaster = {
      url =
        "github:input-output-hk/CardanoLedgerApiBlaster/577e3eb03b5be09354cfdb1c0d0c12e9e16541a0";
      flake = false;
    };
    # #219 A4: the exact nixpkgs rev this repo's justfile already pins for
    # every aiken invocation (`check-onchain`, `aiken fmt`, every
    # `gen-*-vectors` recipe) — aiken v1.1.23. The flake's own `nixpkgs`
    # (haskellNix's `nixpkgs-unstable`) resolves `pkgs.aiken` to v1.1.21, a
    # DIFFERENT compiler than the one the rest of the repo validates
    # against; the blueprint derivation must use the same v1.1.23 the repo
    # already treats as canonical, not whatever `nixpkgs-unstable` happens
    # to carry.
    aikenNixpkgs.url =
      "github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46";
    # The standing repository identity checker remains canonical in
    # scripts/.  Import that directory as data so the flake-owned Blaster
    # runner executes the same checker as `just ci`, never a forked copy.
    blasterIdentityScripts = {
      url = "path:../scripts";
      flake = false;
    };
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, haskellNix, iohkNix, CHaP
    , bundlers, leanBlaster, lean4Nix, leanNixpkgs, plutusCoreBlaster
    , cardanoLedgerApiBlaster, ... }:
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

          leanNixPkgs = import leanNixpkgs {
            inherit system;
            overlays = [
              (lean4Nix.readToolchainFile {
                toolchain = leanBlaster.outPath + "/lean-toolchain";
                binary = true;
              })
              (_final: prev: {
                z3 = prev.z3.overrideAttrs {
                  version = "4.15.2";
                  src = prev.fetchFromGitHub {
                    owner = "Z3Prover";
                    repo = "z3";
                    rev = "z3-4.15.2";
                    hash =
                      "sha256-hUGZdr0VPxZ0mEUpcck1AC0MpyZMjiMw/kK8WX7t0xU=";
                  };
                };
              })
            ];
          };
          leanPkgs = leanNixPkgs.lean;
          cleanBlasterSource = pkgs.lib.cleanSourceWith {
            src = ./blaster;
            filter = path: type:
              let baseName = builtins.baseNameOf (toString path);
              in pkgs.lib.cleanSourceFilter path type && baseName != ".lake"
              && !(pkgs.lib.hasPrefix "result" baseName);
          };
          # #219 A4: the repo-pinned aiken (v1.1.23) — see the `aikenNixpkgs`
          # input comment. Used only by the blueprint derivation, so its
          # compiled bytecode matches what `just check-onchain`/`aiken fmt`/
          # every `gen-*-vectors` recipe already validates against.
          aikenPkgs = import inputs.aikenNixpkgs { inherit system; };

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

          # #176 Slice 1: `data-files` declares docs/assets/swagger/query-api.json
          # (the one repo-root canonical file, via the docsSwagger input
          # above) but this flake's `src` is necessarily scoped to offchain/
          # (haskell.nix re-roots `src` into its own isolated store copy, so
          # a relative symlink pointing above it cannot survive). Cabal's
          # `copy` phase installs the package's data-files for every single
          # component (library, each sublibrary, every exe/test-suite), each
          # built from its own unpacked source copy — so this is a
          # package-level `postUnpack` (not a single component's preBuild),
          # which haskell.nix passes down as the default for every
          # component's own hook. No second hand-maintained copy tracked
          # under offchain/.
          swagger-data-overlay = { lib, pkgs, ... }: {
            packages.cardano-keri.postUnpack = ''
              mkdir -p "$sourceRoot/docs/assets/swagger"
              cp ${inputs.docsSwagger}/query-api.json \
                "$sourceRoot/docs/assets/swagger/query-api.json"
            '';
          };

          project = pkgs.haskell-nix.cabalProject' {
            name = "cardano-keri";
            src = ./.;
            compiler-nix-name = "ghc9123";
            modules = [ fix-libs swagger-data-overlay ];
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
              # Make the in-shell `cabal build` resolve+build CHaP-offline (issue
              # #99, S9c) — i.e. with NO fetch of the secure https CHaP index
              # (hackage over http and the git SRP clones stay live). exactDeps has
              # haskell.nix generate a CABAL_CONFIG that pins the native-lib search
              # paths and the GHC package DB for this shell — the base cabal config
              # the shellHook below augments. It does NOT let cabal reuse the
              # prebuilt CHaP packages wholesale: cabal's solver cannot consume a
              # sublibrary (cardano-node-clients:devnet, io-classes:strict-stm, …)
              # from an already-installed unit, so the full gate must rebuild the
              # CHaP stack from source — which the nix-local CHaP repo (shellHook)
              # then supplies from local source, no CHaP fetch.
              exactDeps = true;
              # Give the in-shell cabal a Nix-LOCAL CHaP repository so the full
              # `cabal build all --enable-tests --project-file=cabal.project.devshell`
              # resolves the CHaP package set and builds the sublibrary-providing
              # stack (io-classes, typed-protocols, ouroboros-network,
              # cardano-node-clients:devnet, …) from LOCAL source, with NO network
              # fetch of the CHaP index (this is CHaP-offline, not fully
              # network-offline — see the hackage/git note below). cabal.project.devshell
              # drops the https CHaP `repository`; here we append a SECURE `file:`
              # repository of the same name pointing at the `CHaP` flake input in the
              # nix store (a complete cabal secure-repo layout: 01-index.tar.gz +
              # root/snapshot/timestamp.json + package/ sources). A secure `file:`
              # repo honours the CHaP index-state (so the solver sees the SAME
              # consistent snapshot as the packaged build — a `file+noindex` repo
              # would instead expose every version and mis-resolve), reads the
              # index/sources from the read-only store, and writes its generated
              # index cache under the explicit `remote-repo-cache`
              # (dist-newstyle/keri-repo-cache) set below — NOT $CABAL_DIR, since the
              # nix-store repo is read-only. We also re-declare hackage: exactDeps'
              # CABAL_CONFIG replaces cabal's default config, and a few CHaP-package
              # deps (e.g. transformers-except, a dep of ouroboros-network) live on
              # hackage; hackage is plain http, which the CHaP-empty runner CAN reach
              # (only the secure https CHaP index was ever the failure), and the
              # source-repository-package git clones stay live too. `just
              # devshell-offchain` and CI run `cabal update
              # --project-file=cabal.project.devshell` first (hackage over http + the
              # local CHaP index generated offline). The augmented config is written
              # under $PWD/dist-newstyle/, which is gitignored both at the repo root
              # (/dist-newstyle/) and under offchain/ (offchain/dist-newstyle/). root-keys
              # mirror offchain/cabal.project.
              shellHook = ''
                if [ -n "$CABAL_CONFIG" ] && [ -f "$CABAL_CONFIG" ]; then
                  mkdir -p "$PWD/dist-newstyle"
                  # Dedicated writable repo-index cache. cabal's secure-repo lock
                  # does not create its parent dir, so pre-create both repos'
                  # subdirs here (empty on a fresh checkout — the CHaP index is
                  # regenerated offline from the nix-local repo, hackage over http).
                  __keri_cache="$PWD/dist-newstyle/keri-repo-cache"
                  mkdir -p "$__keri_cache/hackage.haskell.org" \
                           "$__keri_cache/cardano-haskell-packages"
                  __keri_cfg="$PWD/dist-newstyle/keri-devshell-cabal.config"
                  cat "$CABAL_CONFIG" > "$__keri_cfg"
                  printf '%s\n' \
                    ''' \
                    "remote-repo-cache: $__keri_cache" \
                    ''' \
                    'repository hackage.haskell.org' \
                    '  url: http://hackage.haskell.org/' \
                    ''' \
                    'repository cardano-haskell-packages' \
                    "  url: file:${inputs.CHaP}" \
                    '  secure: True' \
                    '  root-keys:' \
                    '    3e0cce471cf09815f930210f7827266fd09045445d65923e6d0238a6cd15126f' \
                    '    443abb7fb497a134c343faf52f0b659bd7999bc06b7f63fa76dc99d631f9bea1' \
                    '    a86a1f6ce86c449c46666bda44268677abf29b5b2d2eb5ec7af903ec2f117a82' \
                    '    bcec67e8e99cabfa7764d75ad9b158d72bfacf70ca1d0ec8bc6b4406d1bf8413' \
                    '    c00aae8461a256275598500ea0e187588c35a5d5d7454fb57eac18d9edb86a56' \
                    '    d4a35cd3121aa00d18544bb0ac01c3e1691d618f462c46129271bccf39f7e8ee' \
                    >> "$__keri_cfg"
                  export CABAL_CONFIG="$__keri_cfg"
                fi
              '';
            };
          };

          unit-tests-exe =
            project.hsPkgs.cardano-keri.components.tests.unit-tests;
          indexer-tests-exe =
            project.hsPkgs.cardano-keri.components.tests.indexer-tests;
          # #177 Slice 1: the packaged `ckeri` executable itself, top-level
          # (unlike e2eWiring.ckeriRunner below) so `backend-check` can prove
          # its --help/status surface without depending on the Aiken
          # blueprint e2eWiring exists for.
          ckeri-exe = project.hsPkgs.cardano-keri.components.exes.ckeri;
          cli-tests-exe =
            project.hsPkgs.cardano-keri.components.tests.cli-tests;
          ckeri-query-exe =
            project.hsPkgs.cardano-keri.components.exes.ckeri-query;

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
          indexer-tests-runner = pkgs.writeShellApplication {
            name = "indexer-tests";
            text = ''
              exec ${indexer-tests-exe}/bin/indexer-tests "$@"
            '';
          };
          indexer-tests-check = pkgs.runCommand "indexer-tests-check" { } ''
            ${indexer-tests-runner}/bin/indexer-tests
            touch $out
          '';
          # #176 Slice 1: the same "run the compiled test binary" shape as
          # indexer-tests-check/-runner, distinctly named so the immutable
          # slice gate can invoke this slice's contract check by a stable
          # name rather than an hspec --match string.
          query-endpoint-runner = pkgs.writeShellApplication {
            name = "query-endpoint-check";
            text = ''
              exec ${indexer-tests-exe}/bin/indexer-tests "$@"
            '';
          };
          query-endpoint-check = pkgs.runCommand "query-endpoint-check" { } ''
            ${query-endpoint-runner}/bin/query-endpoint-check
            touch $out
          '';
          # #176 Slice 1 Linux-only OCI image: the ckeri-query executable and
          # CA/runtime material only (FR-10) — the RocksDB store and node
          # socket are mounted at deploy time, never baked in. Gated on
          # x86_64-linux the same way e2eWiring is: dockerTools layered
          # images are a Linux-specific artifact and must not break
          # `nix flake check` on aarch64-darwin.
          queryImageWiring = pkgs.lib.optionalAttrs (system == "x86_64-linux")
            (let
              image = pkgs.dockerTools.buildLayeredImage {
                name = "ckeri-query";
                tag = "latest";
                contents = [ ckeri-query-exe pkgs.cacert ];
                config = {
                  Entrypoint = [ "${ckeri-query-exe}/bin/ckeri-query" ];
                  Env = [
                    "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                  ];
                };
              };
            in { inherit image; });
          # #177 Slice 1: one strict-PATH app that proves the focused
          # cli-tests suite passes AND the packaged `ckeri` binary's
          # status/backend surface and fork-retirement absence hold, exposed
          # twice per the runCommand-invokes-app shape so `nix flake check`
          # actually executes it rather than merely building a wrapper. This
          # is `just backend-check`'s focused command.
          backend-check-runner = pkgs.writeShellApplication {
            name = "backend-check";
            runtimeInputs =
              [ ckeri-exe cli-tests-exe pkgs.bash pkgs.coreutils pkgs.gnugrep ];
            text = ''
              cli-tests

              top_help="$(ckeri --help)"
              grep -q "status" <<<"$top_help"
              grep -q "board" <<<"$top_help"
              capability_checker=${./scripts/check-follower-capabilities.sh}
              bash "$capability_checker" --self-test
              bash "$capability_checker" --no-loss "$(command -v ckeri)"
              bash "$capability_checker" --no-leak "$(command -v ckeri)"

              status_help="$(ckeri status --help)"
              grep -q -- "--aid" <<<"$status_help"
              grep -q "CKERI_AID" <<<"$status_help"
              grep -q -- "--backend" <<<"$status_help"
              grep -q "CKERI_BACKEND" <<<"$status_help"
              grep -q -- "--endpoint" <<<"$status_help"
              grep -q "CKERI_ENDPOINT" <<<"$status_help"
              grep -q -- "--store" <<<"$status_help"
              grep -q "CKERI_STORE" <<<"$status_help"
              grep -q -- "--koios-token" <<<"$status_help"
              grep -q "KOIOS_TOKEN" <<<"$status_help"
            '';
          };
          backend-check-check = pkgs.runCommand "backend-check-check" { } ''
            ${backend-check-runner}/bin/backend-check
            touch $out
          '';

          # #177 Slice 2: the strict-PATH app and sandboxed check execute the
          # same canonical in-flake validator and negative-control self-test.
          backend-transcript-check-runner = pkgs.writeShellApplication {
            name = "backend-transcript-check";
            runtimeInputs =
              [ pkgs.bash pkgs.coreutils pkgs.gawk pkgs.gnugrep pkgs.gnused ];
            text = ''
              export BACKEND_TRANSCRIPT_VALIDATOR=${
                ./scripts/check-backend-status-transcripts.sh
              }
              bash ${./scripts/test-backend-status-transcripts.sh}
              bash ${./scripts/check-backend-status-transcripts.sh} \
                --transcript ${./evidence/m1-backend-status-acceptance.txt}
            '';
          };
          backend-transcript-check-check =
            pkgs.runCommand "backend-transcript-check-check" { } ''
              ${backend-transcript-check-runner}/bin/backend-transcript-check
              touch $out
            '';

          # Live-boundary withDevnet e2e wiring. Linux-only (the smoke spawns a
          # real cardano-node); the whole attrset is empty on Darwin so its
          # node/blueprint references are never forced there.
          e2eWiring = pkgs.lib.optionalAttrs (system == "x86_64-linux") (let
            # Flake-owned Aiken blueprint: build plutus.json from the TRACKED
            # onchain sources, yielding an immutable /nix/store blueprint the
            # e2e smoke consumes instead of the gitignored worktree
            # plutus.json (NOTE-016).
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
            # #219 A4: the three `onchain/aiken.lock` GitHub dependencies,
            # vendored as ordinary pinned fetches (each individually
            # immutable — pinned to the exact tag `aiken.lock` names, exactly
            # what a fixed-output fetch is for) rather than left for `aiken
            # build` to re-resolve over the network on every blueprint build.
            # This is the only genuinely impure step (fetching); compiling
            # from a pre-populated `build/packages/` is fully hermetic (see
            # the blueprint derivation below), so vendoring here lets the
            # blueprint itself become an ordinary input-addressed derivation.
            aikenPkgSource = { owner, repo, rev, hash, }:
              pkgs.fetchFromGitHub { inherit owner repo rev hash; };
            aikenStdlib = aikenPkgSource {
              owner = "aiken-lang";
              repo = "stdlib";
              rev = "v2.2.0";
              hash = "sha256-BDaM+JdswlPasHsI03rLl4OR7u5HsbAd3/VFaoiDTh4=";
            };
            aikenMpfsOnchain = aikenPkgSource {
              owner = "cardano-foundation";
              repo = "cardano-mpfs-onchain";
              rev = "v0.1.0";
              hash = "sha256-1NplnTMCKeK7ZasAmn+28bGM6CcWqJp7SvBqhCkuSJM=";
            };
            aikenMerklePatriciaForestry = aikenPkgSource {
              owner = "aiken-lang";
              repo = "merkle-patricia-forestry";
              rev = "v2.0.0";
              hash = "sha256-uHVQxA1dYDuPbH+pf6SkGNBF7nBlDXdULrPFkfUDjzU=";
            };
            # Mirrors the `[[packages]]` records `aiken build` itself writes
            # into `build/packages/packages.toml` on a real fetch — aiken
            # trusts a pre-populated cache in this shape with no network and
            # no re-verification fetch (confirmed empirically under
            # `unshare -rn`, zero network, repo-pinned aiken, rc=0).
            aikenPackagesToml = pkgs.writeText "packages.toml" ''
              [[packages]]
              name = "aiken-lang/stdlib"
              version = "v2.2.0"
              requirements = []
              source = "github"

              [[packages]]
              name = "cardano-foundation/cardano-mpfs-onchain"
              version = "v0.1.0"
              requirements = []
              source = "github"

              [[packages]]
              name = "aiken-lang/merkle-patricia-forestry"
              version = "v2.0.0"
              requirements = []
              source = "github"
            '';
            # #219 A4: ordinary input-addressed derivation (no
            # outputHash/outputHashMode/outputHashAlgo) — any `onchain/`
            # source change is now a Nix input change, so a stale
            # cache-substituted blueprint is structurally impossible. Uses
            # `aikenPkgs.aiken` (the repo-pinned v1.1.23, matching
            # `check-onchain`/`aiken fmt`/every `gen-*-vectors` recipe), not
            # the flake's own `pkgs.aiken` (v1.1.21 via nixpkgs-unstable).
            blueprint = pkgs.stdenvNoCC.mkDerivation {
              name = "keri-plutus-blueprint-silent";
              dontUnpack = true;
              nativeBuildInputs = [ aikenPkgs.aiken ];
              buildPhase = ''
                export HOME="$TMPDIR"
                cp -rL ${onchainSrc}/. ./work
                chmod -R +w ./work
                mkdir -p ./work/build/packages
                cp ${aikenPackagesToml} ./work/build/packages/packages.toml
                cp -rL ${aikenStdlib} \
                  ./work/build/packages/aiken-lang-stdlib
                cp -rL ${aikenMpfsOnchain} \
                  ./work/build/packages/cardano-foundation-cardano-mpfs-onchain
                cp -rL ${aikenMerklePatriciaForestry} \
                  ./work/build/packages/aiken-lang-merkle-patricia-forestry
                chmod -R +w ./work/build
                cd ./work
                aiken build -t silent
              '';
              installPhase = ''
                cp plutus.json "$out"
              '';
            };
            cardanoNode = inputs.cardano-node.packages.${system}.cardano-node;
            cardanoCli = inputs.cardano-node.packages.${system}.cardano-cli;
            e2eExe = project.hsPkgs.cardano-keri.components.tests.e2e-tests;
            ckeriExe = project.hsPkgs.cardano-keri.components.exes.ckeri;
            deploymentTestsExe =
              project.hsPkgs.cardano-keri.components.tests.deployment-tests;
            ckeriRunner = pkgs.writeShellApplication {
              name = "ckeri";
              runtimeInputs = [ ckeriExe cardanoCli pkgs.cacert pkgs.git ];
              text = ''
                export CKERI_BLUEPRINT="''${CKERI_BLUEPRINT:-${blueprint}}"
                export SSL_CERT_FILE="''${SSL_CERT_FILE:-${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt}"
                exec ${ckeriExe}/bin/ckeri "$@"
              '';
            };
            deploymentTestsRunner = pkgs.writeShellApplication {
              name = "deployment-tests";
              runtimeInputs = [ deploymentTestsExe ];
              text = ''
                export KERI_CHECKPOINT_BLUEPRINT="${blueprint}"
                export KERI_BOARD_MANIFEST="${inputs.deployPreprod}/board-manifest.json"
                exec ${deploymentTestsExe}/bin/deployment-tests "$@"
              '';
            };
            deploymentTestsCheck =
              pkgs.runCommand "deployment-tests-check" { } ''
                ${deploymentTestsRunner}/bin/deployment-tests
                touch "$out"
              '';
            # The merged PV11 fixture deliberately shortens epochs from 500 to
            # 100 slots. Register runs against that stock fixture. The legacy
            # Cage smoke still probes a fixed +30s horizon, so preserve its
            # historical 500-slot epoch in an isolated harness copy until its
            # own story makes the builder horizon-aware.
            cageGenesis = pkgs.runCommand "keri-cage-genesis-legacy-horizon" {
              nativeBuildInputs = [ pkgs.coreutils pkgs.jq ];
            } ''
              cp -rL ${inputs.cardano-node-clients}/e2e-test/genesis "$out"
              chmod -R u+w "$out"
              source=${inputs.cardano-node-clients}/e2e-test/genesis/shelley-genesis.json
              target="$out/shelley-genesis.json"

              test "$(${pkgs.jq}/bin/jq -r '.epochLength' "$source")" = 100
              ${pkgs.jq}/bin/jq '.epochLength = 500' "$source" > "$target.new"
              mv "$target.new" "$target"
              test "$(${pkgs.jq}/bin/jq -r '.epochLength' "$target")" = 500

              ${pkgs.jq}/bin/jq -S 'del(.epochLength)' "$source" > source.rest
              ${pkgs.jq}/bin/jq -S 'del(.epochLength)' "$target" > target.rest
              cmp source.rest target.rest
            '';
            # One strict-PATH app exposed twice (apps.e2e via nix run +
            # checks.e2e via a runCommand that invokes it), modeled on
            # cardano-tx-tools/nix/checks.nix. E2E_GENESIS_DIR is the stock
            # pinned cardano-node-clients genesis (maxTxSize 16384); the cage
            # and checkpoint blueprint variables both point at the complete
            # flake-owned production blueprint above.
            runner = pkgs.writeShellApplication {
              name = "e2e";
              # Strict PATH: the E2E executable AND the node binary it spawns
              # must both be listed so the app is self-contained.
              runtimeInputs = [ e2eExe cardanoNode pkgs.coreutils pkgs.which ];
              text = ''
                export E2E_GENESIS_DIR="${inputs.cardano-node-clients}/e2e-test/genesis"
                export KERI_CAGE_BLUEPRINT="${blueprint}"
                export KERI_CHECKPOINT_BLUEPRINT="${blueprint}"
                cd "${inputs.cardano-node-clients}"
                exec e2e-tests --match "#136 register a small identity end to end" "$@"
              '';
            };
            cageRunner = pkgs.writeShellApplication {
              name = "e2e-cage";
              runtimeInputs = [ e2eExe cardanoNode pkgs.coreutils pkgs.which ];
              text = ''
                export E2E_GENESIS_DIR="${cageGenesis}"
                export KERI_CAGE_BLUEPRINT="${blueprint}"
                export KERI_CHECKPOINT_BLUEPRINT="${blueprint}"
                cd "${inputs.cardano-node-clients}"
                exec e2e-tests --match "#99 cage withDevnet Phase-2 smoke" "$@"
              '';
            };
            # #175 SC-1 live composition smoke: real devnet, real checkpoint
            # registration, the production follower over a real N2C socket.
            # Deliberately a standalone app (via `just ci-live`), NOT folded
            # into `checks.e2e`/`checks.follower-e2e` — its RED/GREEN proof
            # runs outside the Nix sandbox so `TMPDIR` from the invoking
            # shell is honored (see justfile's `ci-live`).
            followerRunner = pkgs.writeShellApplication {
              name = "follower-e2e";
              runtimeInputs = [ e2eExe cardanoNode pkgs.coreutils pkgs.which ];
              text = ''
                export E2E_GENESIS_DIR="${inputs.cardano-node-clients}/e2e-test/genesis"
                export KERI_CHECKPOINT_BLUEPRINT="${blueprint}"
                cd "${inputs.cardano-node-clients}"
                exec e2e-tests --match "#175 follower live leg" "$@"
              '';
            };
            check = pkgs.runCommand "e2e-check" { } ''
              ${pkgs.lib.getExe cageRunner}
              ${pkgs.lib.getExe runner}
              touch "$out"
            '';
            # Flake-owned reproducible sweep: same strict-PATH app as `runner`
            # but with the sweep enabled, running ONLY the `cageSweepOne`
            # examples and (re)writing the repo artifact. Heavy (one withDevnet
            # per batch), so it is a dedicated app/CI job — NOT part of the
            # routine `checks.e2e` (which stays the batch-2 correctness smoke).
            # `nix run .#e2e-sweep` from `offchain/` regenerates
            # `e2e/sweep-boundary.md`; each batch ASSERTS its expected node
            # outcome, so a boundary/harness regression fails the run.
            sweepRunner = pkgs.writeShellApplication {
              name = "e2e-sweep";
              runtimeInputs = [ e2eExe cardanoNode pkgs.coreutils pkgs.which ];
              text = ''
                # Preserve the production 16384-byte cap used by the committed
                # cage boundary sweep; only the checkpoint runner is widened.
                export E2E_GENESIS_DIR="${cageGenesis}"
                export KERI_CAGE_BLUEPRINT="${blueprint}"
                export KERI_CHECKPOINT_BLUEPRINT="${blueprint}"
                export KERI_CAGE_SWEEP=1
                export KERI_CAGE_SWEEP_OUT="''${KERI_CAGE_SWEEP_OUT:-$PWD/e2e/sweep-boundary.md}"
                exec e2e-tests --match "sweeps batch size" "$@"
              '';
            };
            # LIGHTWEIGHT consistency check (no devnet): guards the COMMITTED
            # artifact against hand-edits by re-deriving each row's declared
            # aggregate ex-units (8,000,000 + 3,000,000*N mem /
            # 4,000,000,000 + 1,500,000,000*N CPU) and requiring the cage
            # script hash to be present. Safe to run in routine `nix flake
            # check` / CI.
            sweepConsistency = pkgs.runCommand "sweep-consistency" { } ''
              f=${./e2e/sweep-boundary.md}
              ${pkgs.gnugrep}/bin/grep -qE "Cage script hash:.*[0-9a-f]{56}" "$f" \
                || { echo "sweep-boundary.md: missing/short cage script hash"; exit 1; }
              ${pkgs.gawk}/bin/awk -F'|' '
                $2 ~ /^ *[0-9]+ *$/ {
                  n=$2+0; mem=$5+0; cpu=$6+0;
                  emem=8000000+3000000*n; ecpu=4000000000+1500000000*n;
                  if (mem != emem) {
                    printf "row N=%d: agg mem %d != expected %d\n", n, mem, emem; bad=1 }
                  if (cpu != ecpu) {
                    printf "row N=%d: agg cpu %d != expected %d\n", n, cpu, ecpu; bad=1 }
                  rows++
                }
                END {
                  if (rows < 1) { print "sweep-boundary.md: no data rows"; exit 1 }
                  exit bad
                }
              ' "$f"
              touch "$out"
            '';
          in {
            inherit blueprint onchainSrc ckeriRunner deploymentTestsCheck
              deploymentTestsRunner runner followerRunner check sweepRunner
              sweepConsistency;
          });

          # S1 exact-artifact and complete pinned-toolchain surface. This is
          # Linux-only because the sole production blueprint is Linux-only.
          blasterWiring = pkgs.lib.optionalAttrs
            (system == "x86_64-linux" && e2eWiring ? blueprint) (let
              title = "checkpoint.checkpoint.spend";
              expectedBlueprintSha256 =
                "896d2c4642740a26248dc46cdeecbce18730061785e78cfbedc2a13a5c9c577c";
              # #219 A4 follow-up (cross-milestone consumer missed by the
              # original enumeration): ms8's baseline deliberately targets
              # the exact DEPLOYED bytecode (`expectedBlueprintSha256`
              # above), not "whatever the tree currently compiles to" — the
              # live `e2eWiring.blueprint` is correctly fresh after #219 A4
              # and will never equal this frozen value again. Give ms8's
              # check its own STABLE input instead of coupling it to the
              # live blueprint: the exact same fixed-output derivation the
              # live blueprint used to be, scoped only to this baseline, so
              # ms8's pin stays exactly what they pinned regardless of any
              # future onchain/ change. Never route checks.e2e/ckeriRunner/
              # packages.ckeri through this — those need the live blueprint,
              # which is the whole point of A4.
              frozenM8Blueprint = pkgs.stdenvNoCC.mkDerivation {
                name = "keri-plutus-blueprint-m8-baseline";
                dontUnpack = true;
                nativeBuildInputs = [ pkgs.aiken pkgs.cacert ];
                outputHashMode = "flat";
                outputHashAlgo = "sha256";
                outputHash =
                  "sha256-iW0sRkJ0CiYkjcRs3uy84YcwBheF54z77cKhOlycV3w=";
                buildPhase = ''
                  export HOME="$TMPDIR"
                  export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
                  cp -rL ${e2eWiring.onchainSrc}/. ./work
                  chmod -R +w ./work
                  cd ./work
                  rm -rf build plutus.json
                  aiken build -t silent
                '';
                installPhase = ''
                  cp plutus.json "$out"
                '';
              };
              # Slice B freezes a new identity without disturbing the retired
              # pre-#219 artifact above.  This is the ordinary input-addressed
              # source rebuild already used by production consumers, built by
              # the repository's validating Aiken rather than substituted by
              # a declared output hash.
              baselineBlueprint = e2eWiring.blueprint;
              # The baseline commit is the revision of the flake source that
              # supplies e2eWiring.onchainSrc, never a second literal that can
              # drift while still feeding both producer and checker.
              baselineSourceCommit = sourceIdentity;
              baselineVariant = "defaultFunSemanticsVariantE";
              baselineEra = "post-Conway";
              baselineSelection = "explicit-era-binding";
              baselineVersionDerived = "defaultFunSemanticsVariantC";
              baselineVerificationReceipt = "manifest-verification";
              validatingAikenVersion = aikenPkgs.aiken.version;
              baselineToolchain =
                "aiken=${validatingAikenVersion};lean-blaster=${leanBlaster.rev};plutus-core-blaster=${plutusCoreBlaster.rev};cardano-ledger-api-blaster=${cardanoLedgerApiBlaster.rev}";
              sourceIdentity =
                if self ? rev then self.rev else (self.dirtyRev or "dirty");
              lockSha256 = builtins.hashFile "sha256" ./flake.lock;
              leanToolchain = pkgs.lib.removeSuffix "\n"
                (builtins.readFile ./blaster/lean-toolchain);

              leanBlasterPackage = leanBlaster.legacyPackages.${system}.blaster;
              plutusCoreBlasterPackage = leanPkgs.buildLeanPackage {
                name = "PlutusCore";
                roots = [ "PlutusCore" "Cryptograph" ];
                src = plutusCoreBlaster;
                deps = [ leanBlasterPackage ];
              };
              cardanoLedgerApiBlasterPackage = leanPkgs.buildLeanPackage {
                name = "CardanoLedgerApi";
                roots = [ "CardanoLedgerApi" ];
                src = cardanoLedgerApiBlaster;
                deps = [ leanBlasterPackage plutusCoreBlasterPackage ];
              };
              keriBlasterPackage = leanPkgs.buildLeanPackage {
                name = "KeriBlaster";
                roots = [ "KeriBlaster" ];
                # Explicitly named, because the S2 scope check rejects the
                # default entry-point path shape.
                executableName = "s2-evidence";
                src = cleanBlasterSource;
                deps = [
                  leanBlasterPackage
                  plutusCoreBlasterPackage
                  cardanoLedgerApiBlasterPackage
                ];
                # Every module gets z3. The S2 evidence module additionally
                # gets the exact generated production programs placed beside
                # its source, because `buildLeanPackage` builds each module
                # with only its own `.lean` file in the build directory. This
                # is the sole way `#import_uplc "nix-generated/..."` can
                # resolve, so the tracked source keeps its eight literal
                # directives and still cannot read anything but the
                # SHA-bound blueprint's output.
                overrideBuildModAttrs = _final: prev:
                  {
                    buildInputs = (prev.buildInputs or [ ])
                      ++ [ leanNixPkgs.z3 ];
                  } // pkgs.lib.optionalAttrs (prev.name == s2EvidenceModule) {
                    buildCommand = ''
                      mkdir -p nix-generated
                      cp ${s2Artifacts}/*.hex nix-generated/
                    '' + prev.buildCommand;
                  };
              };

              # The compatibility oracle is a Lean executable over the same
              # dependency values as the tracked bridge package.  It loads
              # those packages with Lean.importModules and asks Lean's own
              # global-name resolver; no source-text declaration index sits
              # between the elaborator and the audit verdict.
              compatibilityOraclePackage = leanPkgs.buildLeanPackage {
                name = "CompatibilityOracle";
                roots = [ "CompatibilityOracle" ];
                executableName = "compatibility-oracle";
                src = cleanBlasterSource;
                deps = [
                  leanBlasterPackage
                  plutusCoreBlasterPackage
                  cardanoLedgerApiBlasterPackage
                ];
              };
              compatibilityOracle = compatibilityOraclePackage.executable;

              # The Lean module that carries the eight production imports.
              s2EvidenceModule = "KeriBlaster.S2Evidence";

              # The complete S2 production surface with its declared
              # parameter counts. This list is the selection key set; the
              # blueprint remains the only source of program bytes.
              s2Programs = [
                {
                  title = "checkpoint.checkpoint.spend";
                  params = 6;
                }
                {
                  title = "hash_proof.hash_proof.mint";
                  params = 0;
                }
                {
                  title = "checkpoint_observer.observer_lifecycle.withdraw";
                  params = 3;
                }
                {
                  title = "checkpoint_observer.observer_lifecycle.publish";
                  params = 3;
                }
                {
                  title = "checkpoint_observer.observer_advance.withdraw";
                  params = 1;
                }
                {
                  title = "checkpoint_observer.observer_advance.publish";
                  params = 1;
                }
                {
                  title = "checkpoint_observer.observer_enforcement.withdraw";
                  params = 1;
                }
                {
                  title = "checkpoint_observer.observer_enforcement.publish";
                  params = 1;
                }
              ];

              # The eight exact single-CBOR-hex programs plus a
              # title/params/hash manifest, derived only from the SHA-bound
              # production blueprint. Nothing here is tracked in Git and
              # nothing is hand-written: a substituted or renamed validator
              # fails the cardinality and parameter tests below.
              s2Artifacts = pkgs.runCommand "cardano-keri-s2-uplc-programs" {
                nativeBuildInputs = [ pkgs.coreutils pkgs.jq ];
              } ''
                set -euo pipefail
                mkdir -p "$out"
                blueprint=${frozenM8Blueprint}
                actual_blueprint_sha256="$(sha256sum "$blueprint" | cut -d ' ' -f 1)"
                echo "expected blueprint sha256: ${expectedBlueprintSha256}" >&2
                echo "actual blueprint sha256:   $actual_blueprint_sha256" >&2
                test "$actual_blueprint_sha256" = "${expectedBlueprintSha256}"
                ${pkgs.lib.concatMapStrings (entry: ''
                  title=${pkgs.lib.escapeShellArg entry.title}
                  params=${toString entry.params}
                  test "$(jq -er --arg title "$title" \
                    '[.validators[] | select(.title == $title)] | length' \
                    "$blueprint")" -eq 1
                  test "$(jq -er --arg title "$title" \
                    '.validators[] | select(.title == $title) | (.parameters // []) | length' \
                    "$blueprint")" -eq "$params"
                  jq -er --arg title "$title" \
                    -f ${./blaster/extract-program.jq} "$blueprint" \
                    | tr -d '\n\r[:space:]' > "$out/$title.hex"
                  test -s "$out/$title.hex"
                  printf '%s\t%s\t%s\n' "$title" "$params" \
                    "$(sha256sum "$out/$title.hex" | cut -d ' ' -f 1)" \
                    >> "$out/s2-manifest.tsv"
                '') s2Programs}
                test "$(wc -l < "$out/s2-manifest.tsv")" \
                  -eq ${toString (builtins.length s2Programs)}
                test "$(ls "$out"/*.hex | wc -l)" \
                  -eq ${toString (builtins.length s2Programs)}
              '';

              # The Lean evidence executable. It is linked from the same
              # compiled modules that carry the eight production imports, so
              # it cannot report on anything but the imported values.
              s2Evidence = keriBlasterPackage.executable;

              artifact = pkgs.runCommand "cardano-keri-blaster-artifact" {
                nativeBuildInputs = [ pkgs.coreutils pkgs.jq ];
              } ''
                set -euo pipefail
                mkdir -p "$out"
                blueprint=${frozenM8Blueprint}
                actual_blueprint_sha256="$(sha256sum "$blueprint" | cut -d ' ' -f 1)"
                echo "expected blueprint sha256: ${expectedBlueprintSha256}" >&2
                echo "actual blueprint sha256:   $actual_blueprint_sha256" >&2
                test "$actual_blueprint_sha256" = "${expectedBlueprintSha256}"

                jq -er --arg title "${title}" \
                  -f ${./blaster/extract-program.jq} "$blueprint" \
                  | tr -d '\n\r[:space:]' \
                  > "$out/checkpoint.checkpoint.spend.flat"
                test -s "$out/checkpoint.checkpoint.spend.flat"

                title_count="$(jq -er --arg title "${title}" \
                  '[.validators[] | select(.title == $title)] | length' \
                  "$blueprint")"
                test "$title_count" -eq 1
                program_sha256="$(sha256sum \
                  "$out/checkpoint.checkpoint.spend.flat" | cut -d ' ' -f 1)"

                printf '%s\t%s\n' \
                  blueprint_sha256 "$actual_blueprint_sha256" \
                  title "${title}" \
                  title_count "$title_count" \
                  program_sha256 "$program_sha256" \
                  source_identity "${sourceIdentity}" \
                  lock_sha256 "${lockSha256}" \
                  > "$out/artifact-identities.tsv"
              '';

              auditRunner = pkgs.writeShellApplication {
                name = "blaster-audit";
                runtimeInputs = [
                  pkgs.coreutils
                  pkgs.diffutils
                  pkgs.findutils
                  pkgs.gnugrep
                  pkgs.jq
                ];
                text = ''
                  if (( $# != 0 )); then
                    echo "blaster-audit: accepts no blueprint path or arguments" >&2
                    exit 64
                  fi

                  blueprint=${frozenM8Blueprint}
                  artifact=${artifact}
                  actual_blueprint_sha256="$(sha256sum "$blueprint" | cut -d ' ' -f 1)"
                  echo "expected blueprint sha256: ${expectedBlueprintSha256}" >&2
                  echo "actual blueprint sha256:   $actual_blueprint_sha256" >&2
                  test "$actual_blueprint_sha256" = "${expectedBlueprintSha256}"
                  test "$(jq -er --arg title "${title}" \
                    '[.validators[] | select(.title == $title)] | length' \
                    "$blueprint")" -eq 1

                  selected="$(mktemp)"
                  trap 'rm -f "$selected"' EXIT
                  jq -er --arg title "${title}" \
                    -f ${./blaster/extract-program.jq} "$blueprint" \
                    | tr -d '\n\r[:space:]' > "$selected"
                  cmp "$selected" "$artifact/checkpoint.checkpoint.spend.flat"
                  program_sha256="$(sha256sum "$selected" | cut -d ' ' -f 1)"

                  grep -Fxq $'blueprint_sha256\t'"$actual_blueprint_sha256" \
                    "$artifact/artifact-identities.tsv"
                  grep -Fxq $'title\t${title}' \
                    "$artifact/artifact-identities.tsv"
                  grep -Fxq $'title_count\t1' \
                    "$artifact/artifact-identities.tsv"
                  grep -Fxq $'program_sha256\t'"$program_sha256" \
                    "$artifact/artifact-identities.tsv"
                  grep -Fxq $'source_identity\t${sourceIdentity}' \
                    "$artifact/artifact-identities.tsv"
                  grep -Fxq $'lock_sha256\t${lockSha256}' \
                    "$artifact/artifact-identities.tsv"

                  jq -er \
                    --arg lean_blaster "62d2d59abda37e90097e655b40e27545bba16f3c" \
                    --arg plutus_core "7cf5a78c54b9694ef093bf49edb5d3799b2a49c9" \
                    --arg ledger_api "577e3eb03b5be09354cfdb1c0d0c12e9e16541a0" '
                    def direct($name): .nodes[.nodes[.root].inputs[$name]];
                    (direct("leanBlaster").locked.rev == $lean_blaster)
                    and (direct("leanBlaster").original.rev == $lean_blaster)
                    and (direct("plutusCoreBlaster").locked.rev == $plutus_core)
                    and (direct("plutusCoreBlaster").original.rev == $plutus_core)
                    and (direct("cardanoLedgerApiBlaster").locked.rev == $ledger_api)
                    and (direct("cardanoLedgerApiBlaster").original.rev == $ledger_api)
                    and ([.nodes[]
                      | select(.locked.type? == "github"
                        or .locked.type? == "gitlab"
                        or .locked.type? == "git")
                      | select((.locked.rev? | type) != "string"
                        or (.locked.rev | length) == 0
                        or (.locked.narHash? | type) != "string"
                        or (.locked.narHash | length) == 0)] | length == 0)
                  ' ${./flake.lock} >/dev/null

                  test -e ${keriBlasterPackage.modRoot}
                  if grep -R -n -E '(^|[^[:alnum:]_])(sorry|axiom)([^[:alnum:]_]|$)' \
                    ${cleanBlasterSource}/*.lean; then
                    echo "blaster-audit: forbidden sorry/axiom in S1 Lean source" >&2
                    exit 1
                  fi

                  printf '%s\n' \
                    "artifact.blueprint_sha256=$actual_blueprint_sha256" \
                    "artifact.title=${title}" \
                    "artifact.title_count=1" \
                    "artifact.program_sha256=$program_sha256" \
                    "artifact.source_identity=${sourceIdentity}" \
                    "artifact.lock_sha256=${lockSha256}" \
                    "toolchain.lean=${leanToolchain}" \
                    "toolchain.lean_blaster=${leanBlaster.rev}:${leanBlaster.narHash}" \
                    "toolchain.plutus_core_blaster=${plutusCoreBlaster.rev}:${plutusCoreBlaster.narHash}" \
                    "toolchain.cardano_ledger_api_blaster=${cardanoLedgerApiBlaster.rev}:${cardanoLedgerApiBlaster.narHash}" \
                    "toolchain.z3=${leanNixPkgs.z3.version}:z3-4.15.2:sha256-hUGZdr0VPxZ0mEUpcck1AC0MpyZMjiMw/kK8WX7t0xU=" \
                    "toolchain.aiken=${pkgs.aiken.version}:${nixpkgs.rev}:${nixpkgs.narHash}" \
                    "toolchain.nixpkgs=${nixpkgs.rev}:${nixpkgs.narHash}" \
                    "toolchain.lean4_nix=${lean4Nix.rev}:${lean4Nix.narHash}" \
                    "toolchain.lean_nixpkgs=${leanNixpkgs.rev}:${leanNixpkgs.narHash}" \
                    "PASS: exact production artifact and pinned Blaster toolchain audited"
                '';
              };

              # The all-title manifest is generated only from the source-built
              # blueprint and Nix-bound identity inputs.  No program digest or
              # cardinality is transcribed: the independent standing checker
              # below recomputes them from the blueprint before publication.
              baselineManifest =
                pkgs.runCommand "cardano-keri-post-conway-e-baseline-manifest" {
                  nativeBuildInputs = [ pkgs.coreutils pkgs.jq ];
                } ''
                  set -euo pipefail
                  mkdir -p "$out"
                  export BASELINE_COMMIT=${
                    pkgs.lib.escapeShellArg baselineSourceCommit
                  }
                  export BASELINE_AIKEN=${
                    pkgs.lib.escapeShellArg validatingAikenVersion
                  }
                  export BASELINE_TOOLCHAIN=${
                    pkgs.lib.escapeShellArg baselineToolchain
                  }
                  export BASELINE_VARIANT=${
                    pkgs.lib.escapeShellArg baselineVariant
                  }
                  export BASELINE_ERA=${pkgs.lib.escapeShellArg baselineEra}
                  export BASELINE_SELECTION=${
                    pkgs.lib.escapeShellArg baselineSelection
                  }
                  export BASELINE_VERSION_DERIVED=${
                    pkgs.lib.escapeShellArg baselineVersionDerived
                  }
                  export BASELINE_VERIFICATION_RECEIPT=${
                    pkgs.lib.escapeShellArg baselineVerificationReceipt
                  }
                  export BASELINE_LOCK_SHA256=${
                    pkgs.lib.escapeShellArg lockSha256
                  }
                  export BASELINE_LEAN_BLASTER_REV=${
                    pkgs.lib.escapeShellArg leanBlaster.rev
                  }
                  export BASELINE_PLUTUS_CORE_REV=${
                    pkgs.lib.escapeShellArg plutusCoreBlaster.rev
                  }
                  export BASELINE_LEDGER_API_REV=${
                    pkgs.lib.escapeShellArg cardanoLedgerApiBlaster.rev
                  }
                  bash ${./blaster/make-baseline-manifest.sh} \
                    ${baselineBlueprint} "$out/manifest.json"
                '';

              # A different derivation name forces a genuinely absent output
              # path while preserving the retired builder, inputs, and declared
              # fixed output.  The host-side runner invokes it with substitution
              # disabled and records the observed result; it is never a
              # dependency of the clean baseline or production consumers.
              retiredM8ColdProbe = frozenM8Blueprint.overrideAttrs
                (_: { name = "keri-plutus-blueprint-m8-retired-cold-probe"; });

              # Source-compatibility is a separate, argument-free audit.  Its
              # package identities and source roots come directly from the
              # locked flake inputs; the tracked bridge build is the Lean
              # elaboration oracle, while the scanner makes the complete
              # external reference surface and both controls observable.
              compatibilityAuditRunner = pkgs.writeShellApplication {
                name = "blaster-compatibility-audit";
                runtimeInputs = [
                  compatibilityOracle
                  leanPkgs.lean-all
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.diffutils
                  pkgs.findutils
                  pkgs.gawk
                  pkgs.gnugrep
                  pkgs.gnused
                  pkgs.jq
                  pkgs.nix
                  pkgs.perl
                ];
                text = ''
                  export AUDIT_COMMIT=${sourceIdentity}
                  export AUDIT_TEXT_COLLECTOR=${
                    ./blaster/collect-lean-references.pl
                  }
                  export AUDIT_ILEAN_COLLECTOR=${
                    ./blaster/collect-ilean-references.sh
                  }
                  export AUDIT_SOURCE_ELABORATOR=${
                    ./blaster/elaborate-ilean-root.sh
                  }
                  export AUDIT_ORACLE=${compatibilityOracle}/bin/compatibility-oracle
                  export LEAN_PATH=${keriBlasterPackage.modRoot}
                  export AUDIT_SOURCE_ROOT=${cleanBlasterSource}
                  export AUDIT_SEED=${cleanBlasterSource}/CompatibilityRetiredReference.lean
                  export AUDIT_COLLECTOR_SEED=${cleanBlasterSource}/CompatibilityCollectorClosureReference.lean
                  export AUDIT_NAMESPACE_SEED=${cleanBlasterSource}/CompatibilityNamespaceMoveReference.lean
                  export AUDIT_NESTED_NAMESPACE_SEED=${cleanBlasterSource}/CompatibilityNestedNamespaceReference.lean
                  export AUDIT_UNRECOGNISED_SEED=${cleanBlasterSource}/CompatibilityUnrecognisedReference.lean
                  export AUDIT_LEAN_BLASTER_ROOT=${leanBlaster}
                  export AUDIT_PLUTUS_CORE_ROOT=${plutusCoreBlaster}
                  export AUDIT_LEDGER_API_ROOT=${cardanoLedgerApiBlaster}
                  export AUDIT_LEAN_BLASTER_REV=${leanBlaster.rev}
                  export AUDIT_PLUTUS_CORE_REV=${plutusCoreBlaster.rev}
                  export AUDIT_LEDGER_API_REV=${cardanoLedgerApiBlaster.rev}
                  export AUDIT_TRACKED_BUILD=${keriBlasterPackage.modRoot}
                  export AUDIT_S2_ARTIFACTS=${s2Artifacts}
                  bash ${./blaster/compatibility-audit.sh} "$@"
                '';
              };

              runner = pkgs.writeShellApplication {
                name = "blaster";
                runtimeInputs = [
                  auditRunner
                  compatibilityAuditRunner
                  leanPkgs.lean-all
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.diffutils
                  pkgs.findutils
                  pkgs.gnugrep
                  pkgs.gnused
                  pkgs.jq
                ];
                text = ''
                  bash ${./blaster/test-extraction.sh} \
                    ${./blaster/extract-program.jq}
                  bash ${./blaster/test-production-source.sh} \
                    ${pkgs.lib.getExe auditRunner}
                  ${pkgs.lib.getExe auditRunner}
                  AUDIT_LEAN_BLASTER_ROOT=${leanBlaster} \
                  AUDIT_PLUTUS_CORE_ROOT=${plutusCoreBlaster} \
                  AUDIT_LEDGER_API_ROOT=${cardanoLedgerApiBlaster} \
                    bash ${./blaster/test-ilean-reference-collector.sh} \
                      ${./blaster/collect-ilean-references.sh} \
                      ${./blaster/elaborate-ilean-root.sh} \
                      ${keriBlasterPackage.modRoot} \
                      ${cleanBlasterSource} \
                      ${s2Artifacts}
                  bash ${./blaster/test-compatibility-audit.sh} \
                    ${pkgs.lib.getExe compatibilityAuditRunner} \
                    ${./flake.lock} \
                    ${cleanBlasterSource} \
                    ${cleanBlasterSource}/CompatibilityRetiredReference.lean \
                    ${cleanBlasterSource}/CompatibilityNamespaceMoveReference.lean \
                    ${cleanBlasterSource}/CompatibilityNestedNamespaceReference.lean \
                    ${cleanBlasterSource}/CompatibilityUnrecognisedReference.lean \
                    ${cleanBlasterSource}/CompatibilityCollectorClosureReference.lean \
                    137704294061cc3ed597167b15a586906ba23aba \
                    ${sourceIdentity}

                  # The S2 evidence oracle and its falsification controls run
                  # from this same runner, which is the only path the frozen
                  # slice gate exercises (gate -> just blaster -> nix run
                  # .#blaster -> apps.blaster). A control reachable only by
                  # hand could never fail the gate.
                  # Two identifiers the evidence module cannot compute for
                  # itself. The pinned evaluator revision is taken from the
                  # locked flake input rather than transcribed, so it cannot
                  # disagree with the toolchain audit printed above. The
                  # decisive log SHA-256 refers to a PREVIOUS run's artifact,
                  # which lives outside the build sandbox by construction;
                  # the S2 v2 gate re-hashes that real file before accepting
                  # any row that names it, so this constant cannot drift
                  # unnoticed. Exported so the falsification controls, which
                  # re-invoke the same binary, run under identical inputs.
                  export S2_PINNED_PLUTUS_CORE_REV=${plutusCoreBlaster.rev}
                  export S2_DECISIVE_LOG_SHA256=829f62f062b474ed2ba380d9b230c3dfb57049a95d626b7ada4935ea10f28c59

                  S2_ARTIFACTS=${s2Artifacts} ${s2Evidence}/bin/s2-evidence
                  bash ${./blaster/test-s2-contract.sh} \
                    ${s2Evidence}/bin/s2-evidence \
                    ${s2Artifacts} \
                    ${cleanBlasterSource}/KeriBlaster/S2Evidence.lean

                  # Slice B: recompute and verify the all-title identity with
                  # the canonical repository checker.  The checker recomputes
                  # every title, parameter count, program hash and blueprint
                  # hash from the source-built artifact, then reconciles every
                  # carried record (including the verification receipt).
                  identity_checker=${inputs.blasterIdentityScripts}/check-blaster-identity-consistency.sh
                  identity_manifest=${baselineManifest}/manifest.json
                  identity_blueprint=${baselineBlueprint}
                  identity_out="$(mktemp)"
                  baseline_contract_out="$(mktemp)"
                  producer_contract_out="$(mktemp)"
                  cold_out="$(mktemp)"
                  trap 'rm -f "$identity_out" "$baseline_contract_out" "$producer_contract_out" "$cold_out"' EXIT
                  "$identity_checker" \
                    --identity-manifest "$identity_manifest" \
                    --blueprint "$identity_blueprint" \
                    --expected-commit ${
                      pkgs.lib.escapeShellArg baselineSourceCommit
                    } \
                    --expected-aiken ${
                      pkgs.lib.escapeShellArg validatingAikenVersion
                    } \
                    --expected-variant ${
                      pkgs.lib.escapeShellArg baselineVariant
                    } \
                    --expected-era ${pkgs.lib.escapeShellArg baselineEra} \
                    --expected-selection ${
                      pkgs.lib.escapeShellArg baselineSelection
                    } \
                    --expected-version-derived ${
                      pkgs.lib.escapeShellArg baselineVersionDerived
                    } \
                    --expected-verification-receipt ${
                      pkgs.lib.escapeShellArg baselineVerificationReceipt
                    } \
                    --expected-toolchain ${
                      pkgs.lib.escapeShellArg baselineToolchain
                    } \
                    --expected-lock-sha256 ${
                      pkgs.lib.escapeShellArg lockSha256
                    } \
                    --expected-lean-blaster-rev ${
                      pkgs.lib.escapeShellArg leanBlaster.rev
                    } \
                    --expected-plutus-core-rev ${
                      pkgs.lib.escapeShellArg plutusCoreBlaster.rev
                    } \
                    --expected-ledger-api-rev ${
                      pkgs.lib.escapeShellArg cardanoLedgerApiBlaster.rev
                    } \
                    > "$identity_out"
                  cat "$identity_out"

                  titles="$(jq -er '.programs | length' "$identity_manifest")"
                  programs="$(jq -er '[.programs[].program_sha256] | unique | length' "$identity_manifest")"
                  blueprint_sha256="$(jq -er '.blueprint_sha256' "$identity_manifest")"
                  records_checked="$(sed -n 's/^CBIC_IDENTITY_RESULT records_checked=//p' "$identity_out")"
                  inconsistent="$(sed -n 's/^CBIC_IDENTITY_RESULT inconsistent=//p' "$identity_out")"
                  identity_fields="$(sed -n 's/^CBIC_IDENTITY_RESULT fields=//p' "$identity_out")"
                  reconciled_fields="$(sed -n 's/^CBIC_IDENTITY_RESULT reconciled=//p' "$identity_out")"
                  unexpected_fields="$(sed -n 's/^CBIC_IDENTITY_RESULT unexpected=//p' "$identity_out")"
                  enumerated_by="$(sed -n 's/^CBIC_IDENTITY_RESULT enumerated_by=//p' "$identity_out")"
                  test "$titles" -eq 23
                  test "$programs" -eq 8
                  test "$records_checked" -ge 1
                  test "$inconsistent" -eq 0
                  test "$identity_fields" -ge 1
                  test "$reconciled_fields" -eq "$identity_fields"
                  test "$unexpected_fields" -eq 0
                  test "$enumerated_by" = jq-scalar-paths

                  echo "AUDIT-MANIFEST titles=$titles programs=$programs blueprint_sha256=$blueprint_sha256 aiken=${validatingAikenVersion} commit=${baselineSourceCommit} instrument=baseline-manifest-producer+canonical-checker window=source-blueprint-build outcome=ESTABLISHED"
                  jq -r '.programs[] | [.title, (.params | tostring), .program_sha256] | @tsv' \
                    "$identity_manifest" \
                    | while IFS=$'\t' read -r program_title params program_sha256; do
                        echo "AUDIT-PROGRAM title=$program_title params=$params program_sha256=$program_sha256"
                      done
                  echo "AUDIT-BASELINE built_from=source toolchain=aiken:${validatingAikenVersion} validating_toolchain=aiken:${validatingAikenVersion} agreement=by-construction predicate=validating-aiken-pin-reconciliation outcome=ESTABLISHED"
                  echo "AUDIT-BASELINE-COMMIT declared=${baselineSourceCommit} observed=${sourceIdentity} authority=flake-self-rev agreement=by-construction outcome=ESTABLISHED"
                  echo "AUDIT-EVALUATION-IDENTITY ledger_language=PlutusV3 era=${baselineEra} variant=${baselineVariant} selection=${baselineSelection} version_derived=${baselineVersionDerived} outcome=ESTABLISHED"
                  echo "AUDIT-IDENTITY-CONSISTENCY records_checked=$records_checked inconsistent=$inconsistent instrument=check-blaster-identity-consistency window=all-baseline-manifest-records outcome=ESTABLISHED"
                  echo "AUDIT-IDENTITY-FIELD-COVERAGE fields=$identity_fields reconciled=$reconciled_fields unexpected=$unexpected_fields enumerated_by=$enumerated_by instrument=check-blaster-identity-consistency window=manifest-identity-and-all-record-fields outcome=ESTABLISHED"

                  # The Nix check executes the same app in a build sandbox,
                  # where the deliberately retained /tmp receipt and a nested
                  # nix-daemon cold-store probe are unavailable. The frozen
                  # Slice B gate runs the ordinary host branch below and is the
                  # authority for those two live-boundary controls.
                  if [ "''${CKERI_BLASTER_SANDBOX_CHECK:-0}" != 1 ]; then
                    repo_root="$(cd "$PWD/.." && pwd)"
                    retained_receipt=/tmp/ms-keri-8/e190/t246/evidence/RED-baseline-receipt.md
                    retained_log=/tmp/ms-keri-8/e190/t246/evidence/baseline-blaster.log
                    bash ${./blaster/test-baseline-identity.sh} \
                      "$identity_checker" "$repo_root" \
                      "$retained_receipt" "$retained_log" \
                      | tee "$baseline_contract_out"
                    BASELINE_COMMIT=${pkgs.lib.escapeShellArg baselineSourceCommit} \
                    BASELINE_AIKEN=${pkgs.lib.escapeShellArg validatingAikenVersion} \
                    BASELINE_VARIANT=${pkgs.lib.escapeShellArg baselineVariant} \
                    BASELINE_ERA=${pkgs.lib.escapeShellArg baselineEra} \
                    BASELINE_SELECTION=${pkgs.lib.escapeShellArg baselineSelection} \
                    BASELINE_VERSION_DERIVED=${pkgs.lib.escapeShellArg baselineVersionDerived} \
                    BASELINE_VERIFICATION_RECEIPT=${pkgs.lib.escapeShellArg baselineVerificationReceipt} \
                    BASELINE_TOOLCHAIN=${pkgs.lib.escapeShellArg baselineToolchain} \
                    BASELINE_LOCK_SHA256=${pkgs.lib.escapeShellArg lockSha256} \
                    BASELINE_LEAN_BLASTER_REV=${pkgs.lib.escapeShellArg leanBlaster.rev} \
                    BASELINE_PLUTUS_CORE_REV=${pkgs.lib.escapeShellArg plutusCoreBlaster.rev} \
                    BASELINE_LEDGER_API_REV=${pkgs.lib.escapeShellArg cardanoLedgerApiBlaster.rev} \
                      bash ${./blaster/test-baseline-producer.sh} \
                      ${./blaster/make-baseline-manifest.sh} \
                      "$identity_checker" "$repo_root" \
                      "$identity_blueprint" "$identity_manifest" \
                      | tee "$producer_contract_out"

                    set +e
                    nix build --no-link --option substitute false \
                      .#retired-m8-cold-probe > "$cold_out" 2>&1
                    cold_rc=$?
                    set -e
                    if [ "$cold_rc" -eq 0 ]; then
                      cold_observed=unexpected-success
                      cold_outcome=ESTABLISHED
                    elif grep -qi 'hash mismatch' "$cold_out"; then
                      cold_observed=output-hash-mismatch
                      cold_outcome=REFUTED
                    else
                      cold_observed="nix-build-exit-$cold_rc"
                      cold_outcome=REFUTED
                    fi
                    echo "AUDIT-COLD-STORE artifact=retired-pre-219-fixed-output observed=$cold_observed instrument=nix-build-no-substitute window=single-cold-probe-invocation outcome=$cold_outcome"

                    manifest_rc="$(sed -n 's/^RED-PROOF invariant=INV-246-B5-title rc=\([0-9][0-9]*\).*/\1/p' "$baseline_contract_out")"
                    unnamed_rc="$(sed -n 's/^RED-PROOF invariant=INV-246-B7-unnamed-variant rc=\([0-9][0-9]*\).*/\1/p' "$baseline_contract_out")"
                    historical_rc="$(sed -n 's/^RED-PROOF invariant=INV-246-B6-historical-c-relabel rc=\([0-9][0-9]*\).*/\1/p' "$baseline_contract_out")"
                    retained_rc="$(sed -n 's/^RED-PROOF invariant=INV-246-B8 .* rc=\([0-9][0-9]*\).*/\1/p' "$baseline_contract_out")"
                    for rc in "$manifest_rc" "$unnamed_rc" "$historical_rc" "$retained_rc"; do
                      test "$rc" -gt 0
                    done
                    manifest_moved="$(sed -n 's/^RED-PROOF invariant=INV-246-B5-\([^ ]*\) .*$/\1/p' "$baseline_contract_out" | paste -sd, -)"
                    test -n "$manifest_moved"
                    echo "AUDIT-SELFTEST leg=manifest-mutation rc=$manifest_rc outcome=REFUTED"
                    echo "AUDIT-SELFTEST leg=manifest-mutation rc=$manifest_rc moved=$manifest_moved outcome=REFUTED"
                    echo "AUDIT-SELFTEST leg=unnamed-variant rc=$unnamed_rc outcome=REFUTED"
                    echo "AUDIT-SELFTEST leg=historical-c-relabel rc=$historical_rc outcome=REFUTED"
                    echo "AUDIT-SELFTEST leg=retained-red-receipt rc=$retained_rc outcome=REFUTED"
                    for leg in record-toolchain-mutated \
                               identity-field-without-external-expectation \
                               control-schema-narrower-than-production \
                               baseline-commit-authority-substituted \
                               carried-field-without-reconciled-expectation \
                               coverage-count-not-enumerated; do
                      repair_rc="$(sed -n "s/^REPAIR-SELFTEST leg=$leg rc=\([0-9][0-9]*\) outcome=REFUTED$/\1/p" "$baseline_contract_out")"
                      test "$repair_rc" -gt 0
                      echo "AUDIT-SELFTEST leg=$leg rc=$repair_rc outcome=REFUTED"
                    done
                  fi
                  echo "PASS: blaster app executed controls, extraction, pin audit, and Lean build"
                '';
              };
              check = pkgs.runCommand "blaster-check" { } ''
                CKERI_BLASTER_SANDBOX_CHECK=1 ${pkgs.lib.getExe runner}
                touch "$out"
              '';
            in {
              inherit artifact auditRunner baselineManifest check
                compatibilityAuditRunner retiredM8ColdProbe runner;
              lean = leanPkgs.lean-all;
            });

          # Linux release artifacts (AppImage, DEB, RPM) via NixOS/bundlers.
          # Release artifacts use the bare Cabal version; dev artifacts append
          # -<shortRev> so PR/manual runs never collide with tag publications.
          cabalVersion = pkgs.lib.fileContents
            (pkgs.runCommand "cabal-version" { } ''
              sed -n 's/^version:[[:space:]]*//p' ${
                ./cardano-keri.cabal
              } | head -1 | tr -d '[:space:]' > $out
            '');
          linuxArtifacts =
            if system == "x86_64-linux" && e2eWiring ? ckeriRunner then
              import ./nix/linux-release.nix {
                lib = pkgs.lib;
                bundlers = bundlers.bundlers.${system};
                exePackage = e2eWiring.ckeriRunner;
                version = cabalVersion;
              }
            else
              { };
          linuxDevArtifacts =
            if system == "x86_64-linux" && e2eWiring ? ckeriRunner then
              import ./nix/linux-release.nix {
                lib = pkgs.lib;
                bundlers = bundlers.bundlers.${system};
                exePackage = e2eWiring.ckeriRunner;
                version = cabalVersion;
                shortRev = self.shortRev or "dirty";
              }
            else
              { };

        in {
          packages = {
            unit-tests = unit-tests-exe;
            indexer-tests = indexer-tests-exe;
            ckeri-query = ckeri-query-exe;
            format = format-runner;
            format-check = format-check-runner;
            hlint = hlint-runner;
          } // pkgs.lib.optionalAttrs (queryImageWiring ? image) {
            ckeri-query-image = queryImageWiring.image;
          } // pkgs.lib.optionalAttrs (e2eWiring ? runner) {
            ckeri = e2eWiring.ckeriRunner;
            deployment-tests = e2eWiring.deploymentTestsRunner;
            e2e = e2eWiring.runner;
            e2e-sweep = e2eWiring.sweepRunner;
            follower-e2e = e2eWiring.followerRunner;
            plutus-blueprint = e2eWiring.blueprint;
          } // pkgs.lib.optionalAttrs (blasterWiring ? runner) {
            blaster = blasterWiring.runner;
            blaster-baseline-manifest = blasterWiring.baselineManifest;
            retired-m8-cold-probe = blasterWiring.retiredM8ColdProbe;
            lean = blasterWiring.lean;
          } // pkgs.lib.optionalAttrs (linuxArtifacts ? appimage) {
            ckeri-appimage = linuxArtifacts.appimage;
            ckeri-deb = linuxArtifacts.deb;
            ckeri-rpm = linuxArtifacts.rpm;
            linux-release-artifacts =
              pkgs.runCommand "ckeri-linux-release-artifacts" {
                inherit (linuxArtifacts) appimage deb rpm;
                version = cabalVersion;
              } ''
                mkdir -p $out
                cp "$appimage" "$out/ckeri-$version-x86_64.AppImage"
                cp "$deb"/* $out/ 2>/dev/null || true
                cp "$rpm"/* $out/ 2>/dev/null || true
              '';
          } // pkgs.lib.optionalAttrs (linuxDevArtifacts ? appimage) {
            ckeri-dev-appimage = linuxDevArtifacts.appimage;
            ckeri-dev-deb = linuxDevArtifacts.deb;
            ckeri-dev-rpm = linuxDevArtifacts.rpm;
            linux-dev-release-artifacts =
              pkgs.runCommand "ckeri-linux-dev-release-artifacts" {
                inherit (linuxDevArtifacts) appimage deb rpm;
                version = cabalVersion;
                shortRev = self.shortRev or "dirty";
              } ''
                mkdir -p $out
                cp "$appimage" "$out/ckeri-$version-$shortRev-x86_64.AppImage"
                cp "$deb"/* $out/ 2>/dev/null || true
                cp "$rpm"/* $out/ 2>/dev/null || true
              '';
          };
          checks = {
            unit-tests = unit-tests-check;
            indexer-tests = indexer-tests-check;
            backend-check = backend-check-check;
            backend-transcript-check = backend-transcript-check-check;
            query-endpoint = query-endpoint-check;
          } // pkgs.lib.optionalAttrs (e2eWiring ? check) {
            deployment-tests = e2eWiring.deploymentTestsCheck;
            e2e = e2eWiring.check;
            sweep-consistency = e2eWiring.sweepConsistency;
          } // pkgs.lib.optionalAttrs (blasterWiring ? check) {
            blaster = blasterWiring.check;
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
            indexer-tests = {
              type = "app";
              program = "${indexer-tests-runner}/bin/indexer-tests";
            };
            ckeri-query = {
              type = "app";
              program = "${ckeri-query-exe}/bin/ckeri-query";
            };
            backend-check = {
              type = "app";
              program = "${backend-check-runner}/bin/backend-check";
            };
            backend-transcript-check = {
              type = "app";
              program =
                "${backend-transcript-check-runner}/bin/backend-transcript-check";
            };
            query-endpoint-check = {
              type = "app";
              program = "${query-endpoint-runner}/bin/query-endpoint-check";
            };
          } // pkgs.lib.optionalAttrs (e2eWiring ? runner) {
            ckeri = {
              type = "app";
              program = "${e2eWiring.ckeriRunner}/bin/ckeri";
            };
            deployment-tests = {
              type = "app";
              program =
                "${e2eWiring.deploymentTestsRunner}/bin/deployment-tests";
            };
            e2e = {
              type = "app";
              program = "${e2eWiring.runner}/bin/e2e";
            };
            e2e-sweep = {
              type = "app";
              program = "${e2eWiring.sweepRunner}/bin/e2e-sweep";
            };
            follower-e2e = {
              type = "app";
              program = "${e2eWiring.followerRunner}/bin/follower-e2e";
            };
          } // pkgs.lib.optionalAttrs (blasterWiring ? runner) {
            blaster = {
              type = "app";
              program = "${blasterWiring.runner}/bin/blaster";
            };
          } // pkgs.lib.optionalAttrs (system == "x86_64-linux") {
            linux-artifact-smoke = {
              type = "app";
              program = "${
                  pkgs.writeShellApplication {
                    name = "linux-artifact-smoke";
                    runtimeInputs = [ pkgs.cpio pkgs.rpm pkgs.dpkg ];
                    text = builtins.readFile ./nix/linux-artifact-smoke.sh;
                  }
                }/bin/linux-artifact-smoke";
            };
          };
          devShells.default = project.shell;
        };
    };
}
