# nix/linux-release.nix — flake-owned Linux release artifact builders.
#
# Produces AppImage, DEB, and RPM from the ckeri runner using NixOS/bundlers.
# Release artifacts use the bare Cabal version; dev artifacts append -<shortRev>.
#
# The ckeriRunner already carries pkgs.cacert in runtimeInputs and exports
# SSL_CERT_FILE inside the wrapper, so the CA bundle is in the closure and
# the bundlers preserve it automatically.
#
# The nix-utils DEB/RPM bundlers recover the package version by running
# builtins.parseDrvName on the executable's store-path name. A bare name
# like "ckeri" parses to an empty version, which the bundler then replaces
# with its hardcoded "1.0" default. We therefore override the derivation
# `name` (not just `pname`) below so the store-path name embeds the Cabal
# version, e.g. "ckeri-0.1.0", letting parseDrvName extract the real
# version into the DEB/RPM metadata.
{ lib, bundlers, exePackage, version, shortRev ? null }:

let
  # Set the derivation `name` so the store-path name embeds the Cabal
  # version (the bundlers parse it back out with parseDrvName); also ensure
  # meta.mainProgram is set (bundlers require it for getExe).
  exe = exePackage.overrideAttrs (old: {
    name = "ckeri-${version}";
    meta = (old.meta or { }) // {
      mainProgram = old.meta.mainProgram or "ckeri";
    };
  });

  # For dev artifacts, embed <version>-<shortRev> in the store-path name so
  # the output file and the DEB/RPM package version carry the dev suffix.
  devExe = if shortRev != null then
    exePackage.overrideAttrs (old: {
      name = "ckeri-${version}-${shortRev}";
      meta = (old.meta or { }) // {
        mainProgram = old.meta.mainProgram or "ckeri";
      };
    })
  else
    exe;

  target = if shortRev != null then devExe else exe;
in {
  appimage = bundlers.toAppImage target;
  deb = bundlers.toDEB target;
  rpm = bundlers.toRPM target;
}
