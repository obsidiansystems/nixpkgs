# Every Boost release Nixpkgs carries, one scope apiece, keyed by version.
#
# `generic.nix` builds one release out of the data file generated for it in
# `versions/`, so adding a release is `./update.py 1.92.0` and nothing else --
# the attribute appears from the file being there.
#
# Naming the versions is all-packages.nix's job, as it is for LLVM: this set is
# the equivalent of `llvmPackagesSet`.
{
  lib,
  callPackage,
}:

let
  generic = callPackage ./generic.nix { };
in
lib.mapAttrs' (
  file: _: lib.nameValuePair (lib.removeSuffix ".json" file) (generic (./versions + "/${file}"))
) (lib.filterAttrs (file: _: lib.hasSuffix ".json" file) (builtins.readDir ./versions))
