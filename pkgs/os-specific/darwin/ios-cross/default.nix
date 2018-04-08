{ lib, hostPlatform, targetPlatform
, clang-unwrapped
, binutils-unwrapped
, runCommand
, requireFile
, stdenv
, wrapBintoolsWith
, wrapCCWith
, buildIosSdk, targetIosSdkPkgs
}:

let

# As of 12cc39514, according to @shlevy:
iosPlatformArch = { config, isiPhoneSimulator, ... }: {
  "aarch64-apple-darwin14" = assert !isiPhoneSimulator; "arm64";
  "arm-apple-darwin10"     = assert !isiPhoneSimulator; "armv7";
  "i386-apple-darwin11"    = assert isiPhoneSimulator;  "i386";
  "x86_64-apple-darwin14"  = assert isiPhoneSimulator;  "x86_64";
  "aarch64-apple-ios"      = assert !isiPhoneSimulator; "arm64";
}.${config};

in

rec {
  sdk = rec {
    name = "ios-sdk";
    type = "derivation";
    #outPath = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhone${sdkType}.platform/Developer/SDKs/iPhone${sdkType}${version}.sdk";
    outPath = "/nix/store/rcxax5vv5cv2bw66mcfz8r3k91skfgvn-iPhoneOS.sdk";

    sdkType = if targetPlatform.isiPhoneSimulator then "Simulator" else "OS";
    version = targetPlatform.sdkVer;
  };

  #sdk = requireFile {
  #  name = "iPhoneOS.platform";
  #  sha256 = "0mdqa9w1p6cmli6976v4wi0sw9r4p5prkj7lzfd1877wk11c9c73";
  #  url = "https://example.com";
  #} // {
  #  sdkType = if targetPlatform.isiPhoneSimulator then "Simulator" else "OS";
  #  version = targetPlatform.sdkVer;
  #};

  binutils = wrapBintoolsWith {
    libc = targetIosSdkPkgs.libraries;
    bintools = binutils-unwrapped;
    extraBuildCommands = ''
      echo "-arch ${iosPlatformArch targetPlatform} -L${sdk}/usr/lib" >> $out/nix-support/libc-ldflags-before
      ${lib.optionalString targetPlatform.isiPhoneSimulator "echo '-L${sdk}/usr/lib/system' >> $out/nix-support/libc-ldflags-before"}
      echo "-i${if targetPlatform.isiPhoneSimulator then "os_simulator" else "phoneos"}_version_min 9.0.0" >> $out/nix-support/libc-ldflags-before
    '';
  };

  clang = (wrapCCWith {
    cc = clang-unwrapped;
    bintools = binutils;
    libc = targetIosSdkPkgs.libraries;
    extraBuildCommands = ''
      tr '\n' ' ' < $out/nix-support/cc-cflags > cc-cflags.tmp
      mv cc-cflags.tmp $out/nix-support/cc-cflags
      echo "-target ${targetPlatform.config} -arch ${iosPlatformArch targetPlatform}" >> $out/nix-support/cc-cflags
      echo "-isystem ${sdk}/usr/include -isystem ${sdk}/usr/include/c++/4.2.1/ -stdlib=libstdc++" >> $out/nix-support/cc-cflags
      echo "${if targetPlatform.isiPhoneSimulator then "-mios-simulator-version-min=9.0" else "-miphoneos-version-min=9.0"}" >> $out/nix-support/cc-cflags

      echo "-arch ${iosPlatformArch targetPlatform} -L${sdk}/usr/lib" >> $out/nix-support/libc-ldflags-before
      ${lib.optionalString targetPlatform.isiPhoneSimulator "echo '-L${sdk}/usr/lib/system' >> $out/nix-support/libc-ldflags-before"}
      echo "-i${if targetPlatform.isiPhoneSimulator then "os_simulator" else "phoneos"}_version_min 9.0.0" >> $out/nix-support/libc-ldflags-before
    '';
  }) // {
    inherit sdk;
  };

  libraries = let sdk = buildIosSdk; in runCommand "libSystem-prebuilt" {
    passthru = {
      inherit sdk;
    };
  } ''
    if ! [ -d ${sdk} ]; then
        echo "You must have version ${sdk.version} of the iPhone${sdk.sdkType} sdk installed at ${sdk}" >&2
        exit 1
    fi
    ln -s ${sdk}/usr $out
  '';
}
