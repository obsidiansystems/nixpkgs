{ runCommand
, lib
, llvm
, clang
, binutils
, stdenv
, coreutils
, gnugrep
, buildPackages
, targetPlatform
}:

/* As of this writing, known-good prefix/arch/simulator triples:
 * aarch64-apple-darwin14 | arm64  | false
 * arm-apple-darwin10     | armv7  | false
 * i386-apple-darwin11    | i386   | true
 * x86_64-apple-darwin14  | x86_64 | true
 */

# Apple uses somewhat non-standard names for this. We could fall back on
# `targetPlatform.parsed.cpu.name`, but that would be a more standard one and
# likely to fail. Better just to require something manual.
assert targetPlatform ? arch;

let

  prefix = targetPlatform.config;
  inherit (targetPlatform) arch;
  simulator = targetPlatform.isiPhoneSimulator or false;

  sdkType = if simulator then "Simulator" else "OS";

  sdkVer = targetPlatform.sdkVer;

  sdk = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhone${sdkType}.platform/Developer/SDKs/iPhone${sdkType}${sdkVer}.sdk";

  libc = runCommand "empty-libc" {} "mkdir -p $out/{lib,include}";

in (import ../../../build-support/cc-wrapper {
    inherit stdenv coreutils gnugrep buildPackages;
    nativeTools = false;
    nativeLibc = false;
    binutils = binutils.override {
      inherit libc;
    };
    inherit libc;
    inherit (clang) cc;
    extraBuildCommands = ''
      if ! [ -d ${sdk} ]; then
          echo "You must have ${sdkVer} of the iPhone${sdkType} sdk installed at ${sdk}" >&2
          exit 1
      fi
      # ugh
      tr '\n' ' ' < $out/nix-support/cc-cflags > cc-cflags.tmp
      mv cc-cflags.tmp $out/nix-support/cc-cflags
      echo "-target ${prefix} -arch ${arch} -idirafter ${sdk}/usr/include ${if simulator then "-mios-simulator-version-min=9.0" else "-miphoneos-version-min=9.0"}" >> $out/nix-support/cc-cflags

      echo "-arch ${arch} -L${sdk}/usr/lib ${lib.optionalString simulator "-L${sdk}/usr/lib/system "}-i${if simulator then "os_simulator" else "phoneos"}_version_min 9.0.0" >> $out/nix-support/libc-ldflags-before
    '';
  }) // {
    inherit sdkType sdkVer sdk;
  }
