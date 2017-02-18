{ lib
, localSystem, crossSystem, config, overlays
} @ args:

assert crossSystem.config == "aarch64-unknown-linux-android"
    || crossSystem.config == "arm-unknown-linux-androideabi";

let
  normalCrossStages = import ../cross args;
  len = builtins.length normalCrossStages;
  bootStages = lib.lists.take (len - 2) normalCrossStages;

in bootStages ++ [

  (vanillaPackages: let
    old = (builtins.elemAt normalCrossStages (len - 2)) vanillaPackages;

    inherit (vanillaPackages.androidenv) androidndk;

    ndkInfo = {
      "arm-unknown-linux-androideabi" = { triple = "arm-linux-androideabi"; gccVer = "4.8"; };
      "aarch64-unknown-linux-android" = { triple = "aarch64-linux-android"; gccVer = "4.9"; };
    }.${crossSystem.config} or crossSystem.config;

    # name == android-ndk-r10e ?
    ndkBin =
      "${androidndk}/libexec/${androidndk.name}/toolchains/${ndkInfo.triple}-${ndkInfo.gccVer}/prebuilt/linux-x86_64/bin";

    ndkBins = vanillaPackages.runCommand "ndk-gcc" {
      isGNU = true;
      nativeBuildInputs = [ vanillaPackages.makeWrapper ];
      propgatedBuildInputs = [ androidndk ];
    } ''
      mkdir -p $out/bin
      for prog in ${ndkBin}/${ndkInfo.triple}-*; do
        prog_suffix=$(basename $prog | sed 's/${ndkInfo.triple}-//')
        ln -s $prog $out/bin/${crossSystem.config}-$prog_suffix
      done
    '';

  in old // {
    stdenv = old.stdenv.override (oldStdenv: {
      allowedRequisites = null;
      overrides = self: super: oldStdenv.overrides self super // {
        _androidndk = androidndk;
        binutils = ndkBins;
        inherit ndkBin ndkBins;
        ndkWrappedCC = self.wrapCCCross {
          cc = ndkBins;
          binutils = ndkBins;
          libc = self.libcCross;
        };
      };
    });
  })

  (toolPackages: let
    old = (builtins.elemAt normalCrossStages (len - 1)) toolPackages;
    androidndk = toolPackages._androidndk;
    libs = rec {
      type = "derivation";
      outPath = "${androidndk}/libexec/${androidndk.name}/platforms/android-21/arch-arm64/usr/";
      drvPath = outPath;
    };
  in old // {
    stdenv = toolPackages.makeStdenvCross old.stdenv crossSystem toolPackages.ndkWrappedCC // {
      overrides = self: super: {
        glibcCross = libs;
        libiconvReal = super.libiconvReal.override {
          androidMinimal = true;
        };
        ncurses = super.ncurses.override {
          androidMinimal = true;
        };
      };
    };
  })

]
