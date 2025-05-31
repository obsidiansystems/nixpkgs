{
  lib,
  stdenv,
  fetchFromGitHub,
  evdev-proto,
  testers,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "libudev-zero";
  version = "1.0.3";

  src = fetchFromGitHub {
    owner = "illiliti";
    repo = "libudev-zero";
    rev = finalAttrs.version;
    sha256 = "sha256-NXDof1tfr66ywYhCBDlPa+8DUfFj6YH0dvSaxHFqsXI=";
  };

  env = lib.optionalAttrs stdenv.hostPlatform.isFreeBSD {
    NIX_CFLAGS_COMPILE = "-D__BSD_VISIBLE";
  };

  buildInputs = lib.optionals stdenv.hostPlatform.isFreeBSD [
    evdev-proto
  ];

  postPatch = lib.optionalString stdenv.hostPlatform.isFreeBSD ''
    sed -E -i -e /sysmacros.h/d udev.h
    sed -E -i -e s_linux/netlink.h_netlink/netlink.h_g udev_monitor.c
  '';

  makeFlags = [
    "PREFIX=$(out)"
    "AR=${stdenv.cc.targetPrefix}ar"
  ];

  # Just let the installPhase build stuff, because there's no
  # non-install target that builds everything anyway.
  dontBuild = true;

  installTargets = lib.optionals stdenv.hostPlatform.isStatic "install-static";

  passthru.tests = {
    pkg-config = testers.testMetaPkgConfig finalAttrs.finalPackage;
  };

  meta = {
    homepage = "https://github.com/illiliti/libudev-zero";
    description = "Daemonless replacement for libudev";
    changelog = "https://github.com/illiliti/libudev-zero/releases/tag/${finalAttrs.version}";
    maintainers = with lib.maintainers; [
      qyliss
    ];
    license = lib.licenses.isc;
    pkgConfigModules = [ "libudev" ];
    platforms = lib.platforms.linux ++ lib.platforms.freebsd;
  };
})
