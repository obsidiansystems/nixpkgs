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
    };
    makeMinimal = buildPackages.netbsd.makeMinimal.override { inherit (self) make-rules; };
    mkDerivation = self.callPackage ./pkgs/mkDerivation.nix {
      inherit stdenv;
    };
  });
}
