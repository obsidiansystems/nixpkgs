{ lib, hostPlatform, targetPlatform
, clang
, binutils
, runCommand
, stdenv
, buildIosSdk, targetIosSdkPkgs
}:

let
  # As of 12cc39514, according to @shlevy:
  iosPlatformCheck = { config, arch, isIphoneSimulator, ... }:
    (config == "aarch64-apple-darwin14"
     && arch == "arm64"
     && !(isiPhoneSimulator or false))
    ||
    (config == "arm-apple-darwin10"
     && arch == "armv7"
     && !(isiPhoneSimulator or false))
    ||
    (config == "i386-apple-darwin11"
     && arch == "i386"
     && isiPhoneSimulator)
    ||
    (config == "x86_64-apple-darwin14"
     && arch == "x86_64"
     && isiPhoneSimulator);

in

rec {
  sdk = rec {
    name = "ios-sdk";
    type = "derivation";
    outPath = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhone${sdkType}.platform/Developer/SDKs/iPhone${sdkType}${version}.sdk";

    sdkType = if simulator then "Simulator" else "OS";
    version = targetPlatform.sdkVer;
  };

  binutils = darwin.binutils.override {
    libc = targetIosSdkPkgs.libraries;
  };

  clang = (wrapCCWith {
    inherit (clang) cc;
    bintools = binutils;
    libc = targetIosSdkPkgs.libraries;
    extraBuildCommands = ''
      tr '\n' ' ' < $out/nix-support/cc-cflags > cc-cflags.tmp
      mv cc-cflags.tmp $out/nix-support/cc-cflags
      echo "-target ${targetPlatform.config} -arch ${arch}" >> $out/nix-support/cc-cflags
      echo "-isystem ${sdk}/usr/include -isystem ${sdk}/usr/include/c++/4.2.1/ -stdlib=libstdc++" >> $out/nix-support/cc-cflags
      echo "${if simulator then "-mios-simulator-version-min=9.0" else "-miphoneos-version-min=9.0"}" >> $out/nix-support/cc-cflags

      echo "-arch ${arch} -L${sdk}/usr/lib" >> $out/nix-support/libc-ldflags-before
      ${lib.optionalString simulator "echo '-L${sdk}/usr/lib/system' >> $out/nix-support/libc-ldflags-before"}
      echo "-i${if simulator then "os_simulator" else "phoneos"}_version_min 9.0.0" >> $out/nix-support/libc-ldflags-before
    '';
  }) // {
    inherit sdk;
  };

  libraries = assert iosPlatformCheck hostPlatform; runCommand "libSystem-prebuilt" {
    passthru = {
      sdk = buildIosSdk;
    };
  } ''
    if ! [ -d ${sdk} ]; then
        echo "You must have version ${sdk.version} of the iPhone${sdk.sdkType} sdk installed at ${sdk}" >&2
        exit 1
    fi
    ln -s ${sdk} $out
  '';
}
