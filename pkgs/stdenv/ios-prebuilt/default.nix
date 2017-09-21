{ lib
, localSystem, crossSystem, config, overlays
}:

# As of 12cc39514, according to @shlevy:
assert (crossSystem.config == "aarch64-apple-darwin14" &&
        crossSystem.arch == "arm64" &&
        !(crossSystem.isiPhoneSimulator or false))

    || (crossSystem.config == "arm-apple-darwin10" &&
        crossSystem.arch == "armv7" &&
        !(crossSystem.isiPhoneSimulator or false))

    || (crossSystem.config == "i386-apple-darwin11" &&
        crossSystem.arch == "i386" &&
        crossSystem.isiPhoneSimulator)

    || (crossSystem.config == "x86_64-apple-darwin14" &&
        crossSystem.arch == "x86_64" &&
        crossSystem.isiPhoneSimulator);

let
  bootStages = import ../. {
    inherit lib localSystem overlays;
    crossSystem = null;
    # Ignore custom stdenvs when cross compiling for compatability
    config = builtins.removeAttrs config [ "replaceStdenv" ];
  };

  inherit (crossSystem) arch;
  simulator = crossSystem.isiPhoneSimulator or false;

  sdkType = if simulator then "Simulator" else "OS";

  sdkVer = crossSystem.sdkVer;

  sdk = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhone${sdkType}.platform/Developer/SDKs/iPhone${sdkType}${sdkVer}.sdk";

in bootStages ++ [

  (vanillaPackages:  {
    inherit config overlays;
    selfBuild = false;
    stdenv = vanillaPackages.stdenv.override (oldStdenv: {
      targetPlatform = crossSystem;
      allowedRequisites = null;
      overrides = self: super: oldStdenv.overrides self super // {
        libcCross = self.__targetPackages.iosLibSystem;
        iosBinutils = self.darwin.binutils.override {
          libc = self.libcCross;
          extraBuildCommands = ''
            if ! [ -d ${sdk} ]; then
                echo "You must have ${sdkVer} of the iPhone${sdkType} sdk installed at ${sdk}" >&2
                exit 1
            fi
          '';
        };
        iosClang = (self.wrapCCWith {
          inherit (self.clang) cc;
          binutils = self.iosBinutils;
          libc = self.libcCross;
          extraBuildCommands = ''
            tr '\n' ' ' < $out/nix-support/cc-cflags > cc-cflags.tmp
            mv cc-cflags.tmp $out/nix-support/cc-cflags
            echo "-target ${crossSystem.config} -arch ${arch}" >> $out/nix-support/cc-cflags
            echo "-isystem ${sdk}/usr/include -isystem ${sdk}/usr/include/c++/4.2.1/ -stdlib=libstdc++" >> $out/nix-support/cc-cflags
            echo "${if simulator then "-mios-simulator-version-min=9.0" else "-miphoneos-version-min=9.0"}" >> $out/nix-support/cc-cflags

            echo "-arch ${arch} -L${sdk}/usr/lib" >> $out/nix-support/libc-ldflags-before
            ${lib.optionalString simulator "echo '-L${sdk}/usr/lib/system' >> $out/nix-support/libc-ldflags-before"}
            echo "-i${if simulator then "os_simulator" else "phoneos"}_version_min 9.0.0" >> $out/nix-support/libc-ldflags-before
          '';
        }) // {
          inherit sdkType sdkVer sdk;
        };
      };
    });
  })

  (toolPackages: {
    inherit config overlays;
    selfBuild = false;
    stdenv = toolPackages.makeStdenvCross {
      inherit (toolPackages) stdenv;
      buildPlatform = localSystem;
      hostPlatform = crossSystem;
      targetPlatform = crossSystem;
      cc = toolPackages.iosClang;
      overrides = self: super: {
        iosLibSystem = rec {
          type = "derivation";
          outPath = sdk + "/usr";
          drvPath = outPath;
        };
      };
    };
  })

]
