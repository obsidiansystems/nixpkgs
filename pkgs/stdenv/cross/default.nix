{ lib
, localSystem, crossSystem, config, overlays
}:

let
  bootStages = import ../. {
    inherit lib localSystem overlays;
    crossSystem = null;
    # Ignore custom stdenvs when cross compiling for compatability
    config = builtins.removeAttrs config [ "replaceStdenv" ];
  };

in bootStages ++ [

  # GCC boot Packages
  (vanillaPackages: {
    buildPlatform = localSystem;
    hostPlatform = localSystem;
    targetPlatform = crossSystem;
    inherit config overlays;
    selfBuild = false;
    # It's OK to change the built-time dependencies
    allowCustomOverrides = true;
    stdenv = vanillaPackages.stdenv.override {
      overrides = self: super: with self; vanillaPackages.stdenv.overrides self super // {

        gccCrossStageStatic = let
          libcCross1 =
            if targetPlatform.libc == "msvcrt" then windows.mingw_w64_headers
            else if targetPlatform.libc == "libSystem" then darwin.xcode
            else null;
          in wrapGCCCross {
            gcc = super.gcc.cc.override {
              crossStageStatic = true;
              langCC = false;
              libcCross = libcCross1;
              enableShared = false;
            };
            inherit (__targetPackages) libc;
            cross = targetPlatform;
            inherit binutils;
        };

        # Only needed for mingw builds
        gccCrossMingw2 = wrapGCCCross {
          gcc = gccCrossStageStatic.gcc;
          libc = windows.mingw_headers2;
          cross = targetPlatform;
          inherit binutils;
        };

      };
    };
  })

  # Build packages
  (gccBootPackages: let vanillaPackages = gccBootPackages.stdenv.__bootPackages; in {
    buildPlatform = localSystem;
    hostPlatform = localSystem;
    targetPlatform = crossSystem;
    inherit config overlays;
    selfBuild = false;
    # These packages should depend on native packages, ugly hack
    skipPrev = true;
    # It's OK to change the built-time dependencies
    allowCustomOverrides = true;
    stdenv = vanillaPackages.stdenv.override {

      cc = gccBootPackages.gccCrossStageStatic;

      overrides = self: super: with self; vanillaPackages.stdenv.overrides self super // {
        inherit (gccBootPackages) gccCrossStageStatic gccCrossMingw2;

        gccCrossStageFinal = wrapGCCCross {
          gcc = gcc.cc.override {
            crossStageStatic = false;
            # Why is this needed?
            inherit (forcedNativePackages) binutils;
          };
          inherit libc;
          cross = targetPlatform;
          inherit binutils;
        };
      };

    };
  })


  # Run Packages
  (buildPackages: {
    buildPlatform = localSystem;
    hostPlatform = crossSystem;
    targetPlatform = crossSystem;
    inherit config overlays;
    selfBuild = false;
    stdenv = if crossSystem.useiOSCross or false
      then let
          inherit (buildPackages.darwin.ios-cross) cc binutils;
        in buildPackages.makeStdenvCross
          buildPackages.stdenv crossSystem
          binutils cc
      else buildPackages.makeStdenvCross
        (buildPackages.stdenv.override {
          overrides = {
            inherit (buildPackages) gccCrossStageStatic gccCrossMingw2
              gccCrossStageFinal;
          };
        })
        crossSystem
        buildPackages.binutils
        buildPackages.gccCrossStageFinal;
  })

]
