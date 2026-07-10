{
  description = "Pinned Aiken toolchain for the BLAKE3 Plutus spike";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      version = "1.1.23";

      releases = {
        x86_64-linux = {
          target = "x86_64-unknown-linux-musl";
          hash = "sha256-uYxMy62l418VukF6Uocq6vDGWZiu13NRdpzl/SUGtXA=";
        };
        aarch64-linux = {
          target = "aarch64-unknown-linux-musl";
          hash = "sha256-cqQLThuOIhnE1lVZDWpuho2Fg4bbeAo2lxvTqvTYkpA=";
        };
        x86_64-darwin = {
          target = "x86_64-apple-darwin";
          hash = "sha256-ePHJYuITrd14ZmTN9cJ5KSRIMyvHj1codAQZsgyEDGM=";
        };
        aarch64-darwin = {
          target = "aarch64-apple-darwin";
          hash = "sha256-bAOwcqWZ4YmazPdmbEby2BHVbUYF+bsJev84BHzo+gI=";
        };
      };

      systems = builtins.attrNames releases;
      forAllSystems = nixpkgs.lib.genAttrs systems;

      mkAiken =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          release = releases.${system};
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = "aiken";
          inherit version;

          src = pkgs.fetchurl {
            url = "https://github.com/aiken-lang/aiken/releases/download/v${version}/aiken-${release.target}.tar.gz";
            inherit (release) hash;
          };

          sourceRoot = "aiken-${release.target}";
          dontBuild = true;

          installPhase = ''
            runHook preInstall
            install -Dm755 aiken "$out/bin/aiken"
            runHook postInstall
          '';

          meta = {
            description = "Aiken smart contract language and toolchain";
            homepage = "https://aiken-lang.org";
            license = nixpkgs.lib.licenses.asl20;
            mainProgram = "aiken";
            platforms = systems;
          };
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          aiken = mkAiken system;
        in
        {
          inherit aiken;
          default = aiken;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShellNoCC {
            packages = [
              (mkAiken system)
              pkgs.nixfmt
            ];
          };
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          aiken = mkAiken system;
        in
        {
          compiler-version =
            pkgs.runCommand "aiken-${version}-version"
              {
                nativeBuildInputs = [ pkgs.gnugrep ];
              }
              ''
                ${aiken}/bin/aiken --version \
                  | grep -F "aiken v${version}+" > "$out"
              '';

          nix-format =
            pkgs.runCommand "blake3-spike-nix-format"
              {
                nativeBuildInputs = [ pkgs.nixfmt ];
              }
              ''
                nixfmt --check ${./flake.nix}
                touch "$out"
              '';
        }
      );
    };
}
