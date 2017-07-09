{ stdenvNoCC, lib, buildPackages
, buildPlatform, hostPlatform
, fetchurl, perl
}:

assert hostPlatform.isLinux;

let
  version = "2.4.37.9";
  inherit (hostPlatform.platform) kernelHeadersBaseConfig;
in

stdenvNoCC.mkDerivation {
  name = "linux-headers-${version}";

  src = fetchurl {
    url = "mirror://kernel/linux/kernel/v2.4/linux-${version}.tar.bz2";
    sha256 = "08rca9lcb5l5w483hgaqk8pi2njd7cmwpkifjqxwlb3g8liz4r5g";
  };

  targetConfig = if hostPlatform != buildPlatform then hostPlatform.config else null;

  platform = hostPlatform.platform.kernelArch or (
    if hostPlatform.system == "i686-linux" then "i386" else
    if hostPlatform.system == "x86_64-linux" then "x86_64" else
    if hostPlatform.system == "powerpc-linux" then "powerpc" else
    if hostPlatform.isArm then "arm" else
    abort "don't know what the kernel include directory is called for this platform");

  preNativeBuildInputs = [ buildPackages.stdenv.cc ];
  nativeBuildInputs = [ perl ];

  patchPhase = ''
    sed -i s,/bin/pwd,pwd, Makefile
  '';

  extraIncludeDirs = lib.optional hostPlatform.isPowerPC ["ppc"];

  buildPhase = ''
    cp arch/$platform/${kernelHeadersBaseConfig} .config
    make mrproper symlinks include/linux/{version,compile}.h \
      ARCH=$platform
    yes "" | make oldconfig ARCH=$platform
  '';

  installPhase = ''
    mkdir -p $out/include
    cp -a include/{asm,asm-$platform,acpi,linux,pcmcia,scsi,video} \
      $out/include
  '';
}
