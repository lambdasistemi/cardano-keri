{
  description = "Hermetic keripy oracle for cardano-keri #106 fixtures";

  # keripy is not in nixpkgs. This self-contained flake builds a reproducible
  # keripy environment from the committed uv.lock via uv2nix, so keripy is
  # available in a nix shell / nix run WITHOUT an ad-hoc network `uv pip install`.
  # (Analogous to spikes/88-blake3-plutus keeping its own pinned toolchain flake.)
  #
  #   nix develop            -> shell with the keri venv + libsodium on the path
  #   nix run .#gen          -> regenerate the committed fixtures
  #
  # pysodium resolves libsodium through ctypes.util.find_library, which ignores
  # LD_LIBRARY_PATH on NixOS, so SODIUM_LIB is exported and gen_fixtures.py
  # patches find_library to it.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, uv2nix, pyproject-nix, pyproject-build-systems, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        python = pkgs.python312;

        workspace =
          uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

        overlay = workspace.mkPyprojectOverlay {
          sourcePreference = "wheel";
        };

        # hio, keri, and pysodium are the only sdist-only deps in the lock (all
        # others resolve to wheels under sourcePreference = "wheel"). They are
        # legacy setup.py builds that don't declare setuptools/wheel, so uv2nix
        # fails them with "No module named 'setuptools'". Inject the backend.
        sdistOnly = [ "hio" "keri" "pysodium" ];
        buildFixups = final: prev:
          builtins.listToAttrs (map
            (name: {
              inherit name;
              value = prev.${name}.overrideAttrs (old: {
                nativeBuildInputs = (old.nativeBuildInputs or [ ])
                  ++ final.resolveBuildSystem { setuptools = [ ]; wheel = [ ]; };
              });
            })
            sdistOnly);

        pythonSet =
          (pkgs.callPackage pyproject-nix.build.packages { inherit python; })
          .overrideScope (pkgs.lib.composeManyExtensions [
            pyproject-build-systems.overlays.default
            overlay
            buildFixups
          ]);

        venv = pythonSet.mkVirtualEnv "keri-fixtures-env"
          workspace.deps.default;

        sodiumLib = "${pkgs.libsodium}/lib/libsodium.so";

        genScript = pkgs.writeShellApplication {
          name = "gen-fixtures";
          runtimeInputs = [ venv ];
          text = ''
            export SODIUM_LIB=${sodiumLib}
            exec python ${./gen_fixtures.py}
          '';
        };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [ venv pkgs.libsodium ];
          env.SODIUM_LIB = sodiumLib;
          shellHook = ''
            echo "keripy $(python -c 'import keri; print(keri.__version__)') available (SODIUM_LIB set)"
          '';
        };

        apps.gen = {
          type = "app";
          program = "${genScript}/bin/gen-fixtures";
        };
        apps.default = { type = "app"; program = "${genScript}/bin/gen-fixtures"; };
      });
}
