{
  lib,
  runCommand,
  buildPackages,
  fileGlobs ? [
    "intel/iwlwifi/iwlwifi-*.ucode"
    "intel/iwlwifi/iwlwifi-*.pnwm"
  ],
}:
let
  linux-firmware = buildPackages.linux-firmware;
  globText = if (builtins.length fileGlobs) == 1 then builtins.elemAt fileGlobs 0 else "{${lib.strings.concatStringsSep "," fileGlobs}}";
in runCommand "wifi-firmware-${linux-firmware.version}" {
  meta.license = linux-firmware.meta.license;
} ''
  mkdir -p $out/kernel
  cp -a ${linux-firmware}/lib/firmware/${globText} $out/kernel
''
