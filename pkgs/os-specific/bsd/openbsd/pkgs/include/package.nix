{ lib
, mkDerivation
, makeMinimal
, bsdSetupHook
, buildPackages
, pax
, perl
}:
mkDerivation {
  path = "include";

  extraPaths = [
    "lib"
    "sys"
  ];

  nativeBuildInputs =  [
    bsdSetupHook
    makeMinimal
    pax
    perl

    # HACK use NetBSD's for now
    buildPackages.netbsd.install
    buildPackages.netbsd.rpcgen
    buildPackages.netbsd.mtree
  ];

  patches = [
    ./skip-rdirs.patch
    ./no-perms.patch
  ];

  postPatch = ''
    substituteInPlace $BSDSRCDIR/include/Makefile \
     --replace '-o ''${BINOWN}' "" \
     --replace '-g ''${BINGRP}' "" \
     --replace ' ''${INSTALL_COPY}' "" \
     --replace "pax" "pwd; pax"
    find "$BSDSRCDIR" -name Makefile -exec \
      sed -i -E \
        -e "s|/usr/include|$out/include|" \
        {} \;
  '';

  makeFlags = [
    "RPCGEN_CPP=${buildPackages.stdenv.cc.cc}/bin/cpp"
    "-B"
  ];

  headersOnly = true;

  MK_HESIOD = "yes";

  meta.platforms = lib.platforms.openbsd;
}
