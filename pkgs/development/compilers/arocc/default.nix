{
  lib,
  fetchFromGitHub,
  callPackage,
  pkgs,
  buildPackages,
  targetPackages,
  zig,
}:
let
  versions = [
    {
      inherit zig;
      version = "0-unstable-2026-04-02";
      src = fetchFromGitHub {
        owner = "Vexu";
        repo = "arocc";
        rev = "5f5a050569a95ecc40a426f0c3666ae7ef987ede";
        hash = "sha256-f8Z0SXWx5Uia2TCMB5SUpcO8+xUnaWk32Oknva7xcxw=";
      };
    }
  ];

  mkPackage =
    {
      zig,
      version,
      src,
    }:
    callPackage ./package.nix { inherit zig version src; };

  pkgsList = lib.map mkPackage versions;

  # What this stage provides: the unwrapped compilers only. The wrapping
  # happens in `_tools`, in the stage that consumes them.
  pkgsAttrsUnwrapped = lib.listToAttrs (
    lib.map (pkg: lib.nameValuePair "${pkg.version}-unwrapped" pkg) pkgsList
  );
in
{
  latest-unwrapped = lib.last pkgsList;

  # The toolchain the previous stage handed us, in the shape every toolchain set
  # shares; see `pkgs/top-level/stage-tools.nix`. Wrapped *here*, from
  # `buildPackages.aroccPackages`'s unwrapped compiler.
  #
  # Arocc is a C compiler only and brings no bintools or runtime of its own, so
  # the bintools are the stage's, and one `cc` serves all three rungs.
  _tools =
    let
      # This stage's wrapper, built by the previous stage. Not a top-level
      # `wrapCCWith`: that is now the forward-facing alias.
      inherit (pkgs._tools) wrapCCWith;
      prev = buildPackages.aroccPackages;
    in
    {
      inherit (pkgs._tools)
        bintools-unwrapped
        bintools
        bintoolsNoLibc
        ;
      cc-unwrapped = prev.latest-unwrapped;
      cc = wrapCCWith { cc = prev.latest-unwrapped; };
      ccNoLibc = pkgs.aroccPackages._tools.cc;
      ccNoLibs = pkgs.aroccPackages._tools.cc;
    };
}
// pkgsAttrsUnwrapped
// lib.optionalAttrs (pkgs.config.allowAliases && pkgs.targetPackages ? _tools) (
  # Deprecated: these names have always meant the compiler this stage hands to
  # its successor, which is exactly that successor's `_tools`.
  {
    latest = targetPackages.aroccPackages._tools.cc;
  }
  // lib.listToAttrs (
    lib.map (pkg: lib.nameValuePair pkg.version targetPackages.aroccPackages._tools.cc) pkgsList
  )
)
