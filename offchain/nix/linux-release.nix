# nix/linux-release.nix — flake-owned Linux release artifact builders.
#
# Produces AppImage, DEB, and RPM from the ckeri runner using NixOS/bundlers.
# Release artifacts use the bare Cabal version; dev artifacts append -<shortRev>.
#
# The ckeriRunner already carries pkgs.cacert in runtimeInputs and exports
# SSL_CERT_FILE inside the wrapper, so the CA bundle is in the closure and
# the bundlers preserve it automatically.
#
# Known limitation: DEB/RPM package metadata shows version "1.0" (the
# nix-utils bundler default) because writeShellApplication carries no
# version attribute for it to read. The binary itself reports the correct
# Cabal version in all three formats; only the package manager metadata is
# wrong. Fixing this requires a different derivation shape (out of scope
# for this slice).
{ lib, bundlers, exePackage, version, shortRev ? null }:

let
  # Ensure meta.mainProgram is set (bundlers require it for getExe).
  exe = exePackage.overrideAttrs (old: {
    meta = (old.meta or { }) // {
      mainProgram = old.meta.mainProgram or "ckeri";
    };
  });

  # For dev artifacts, rename the package so the output file carries
  # the <version>-<shortRev> suffix.
  devExe =
    if shortRev != null then
      exePackage.overrideAttrs (old: {
        pname = "${old.pname or "ckeri"}-${version}-${shortRev}";
        meta = (old.meta or { }) // {
          mainProgram = old.meta.mainProgram or "ckeri";
        };
      })
    else
      exe;

  target = if shortRev != null then devExe else exe;
in
{
  appimage = bundlers.toAppImage target;
  deb = bundlers.toDEB target;
  rpm = bundlers.toRPM target;
}
