{ stdenv, lib, stdenvNoCC
, makeScopeWithSplicing', generateSplicesForMkScope
, buildPackages
}:

makeScopeWithSplicing' {
  otherSplices = generateSplicesForMkScope "openbsd";
  f = (self: lib.packagesFromDirectoryRecursive {
    callPackage = self.callPackage;
    directory = ./pkgs;
  } // {
    libc = self.callPackage ./pkgs/libc/package.nix {
      inherit (buildPackages.netbsd) makeMinimal;
    };
    mkDerivation = self.callPackage ./pkgs/mkDerivation.nix {
      inherit stdenv;
      inherit (buildPackages.netbsd) makeMinimal;
      # inherit (buildPackages.openbsd) makeMinimal install tsort;
    };

  });
}
