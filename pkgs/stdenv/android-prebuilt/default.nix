{ lib
, localSystem, crossSystem, config, overlays
} @ args:

assert crossSystem.config == "aarch64-linux-android";

let
  normalCrossStages = import ../cross args;
  len = builtins.length normalCrossStages;
  bootStages = lib.lists.take (len - 2) normalCrossStages;

in bootStages ++ [

  (vanillaPackages: let
    old = (builtins.elemAt normalCrossStages (len - 2)) vanillaPackages;

    inherit (vanillaPackages.androidenv) androidndk;

    # name == android-ndk-r10e ?
    ndkBin =
      "${androidndk}/libexec/${androidndk.name}/toolchains/${crossSystem.config}-4.9/prebuilt/linux-x86_64/bin/";

    ndkBins = vanillaPackages.runCommand "ndk-gcc" {
      isGNU = true;
      nativeBuildInputs = [ vanillaPackages.makeWrapper ];
      propgatedBuildInputs = [ androidndk ];
    } ''
      mkdir -p $out/bin
      for prog in ${ndkBin}/${crossSystem.config}-*; do
        ln -s $prog $out/bin/$(basename $prog)
      done
      find $out
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
