{ lib
, localSystem, crossSystem, config, overlays
}:

assert crossSystem.config == "aarch64-unknown-linux-android"
    || crossSystem.config == "arm-unknown-linux-androideabi";

let
  bootStages = import ../. {
    inherit lib localSystem overlays;
    crossSystem = null;
    # Ignore custom stdenvs when cross compiling for compatability
    config = builtins.removeAttrs config [ "replaceStdenv" ];
  };

  ndkInfo = {
    "arm-unknown-linux-androideabi" = {
      arch = "arm";
      triple = "arm-linux-androideabi";
      gccVer = "4.8";
    };
    "aarch64-unknown-linux-android" = {
      arch = "arm64";
      triple = "aarch64-linux-android";
      gccVer = "4.9";
    };
  }.${crossSystem.config} or crossSystem.config;

in bootStages ++ [

  (vanillaPackages: let
    inherit (vanillaPackages.androidenv) androidndk;

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

  in {
    inherit config overlays;
    selfBuild = false;
    stdenv = vanillaPackages.stdenv.override (oldStdenv: {
      targetPlatform = crossSystem;
      allowedRequisites = null;
      overrides = self: super: oldStdenv.overrides self super // {
        _androidndk = androidndk;
        binutils = self.ndkBinutils;
        inherit ndkBin ndkBins;
        ndkBinutils = self.binutilsWrapperFun {
          nativeTools = false;
          nativeLibc = false;
          libc = self.libcCross;
          binutils = ndkBins;
          extraBuildCommands = "";
        };
        ndkWrappedCC = self.wrapCCCross {
          cc = ndkBins;
          binutils = self.ndkBinutils;
          libc = self.libcCross;
          extraBuildCommands =
            # GCC 4.9 is the first relase with "-fstack-protector"
            lib.optionalString (lib.versionOlder ndkInfo.gccVer "4.9") ''
              sed -E \
              -i $out/nix-support/add-hardening.sh \
              -e 's|(-fstack-protector)-strong|\1|g'
            '';
        };
      };
    });
  })

  (toolPackages: let
    androidndk = toolPackages._androidndk;
    libs = rec {
      type = "derivation";
      outPath = "${androidndk}/libexec/${androidndk.name}/platforms/android-21/arch-${ndkInfo.arch}/usr/";
      drvPath = outPath;
    };
  in {
    inherit config overlays;
    selfBuild = false;
    stdenv = toolPackages.makeStdenvCross {
      inherit (toolPackages) stdenv;
      buildPlatform = localSystem;
      hostPlatform = crossSystem;
      targetPlatform = crossSystem;
      cc = toolPackages.ndkWrappedCC;
      overrides = self: super: {
        bionic = libs;
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
