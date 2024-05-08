{ lib, mkDerivation
, bsdSetupHook
, buildPackages
, pax
, perl
}:
mkDerivation {
  path = "include";

  extraPaths = [
    # "contrib/libc-vis"
    # "etc/mtree/BSD.include.dist"
    "lib"
    "sys"
  ];

  nativeBuildInputs =  [
    bsdSetupHook
    # makeMinimal
    buildPackages.netbsd.install
    buildPackages.netbsd.rpcgen
    # mandoc groff rsync rpcgen

    # HACK use NetBSD's for now
    buildPackages.netbsd.mtree
    buildPackages.netbsd.makeMinimal
    pax
    perl
  ];

  patches = [
    ./rdirs.patch
  ];

  # preIncludes = ''
  #   echo starting pax
  #   mkdir $out
  #   pax -rw -pa -s "|\.\./sys/arch/amd64/include||"  ../sys/arch/amd64/include/*.h $out/
  #   echo pax succeeded
  # '';
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

  # multiple header dirs, see above
  # postConfigure = ''
  #   makeFlags=''${makeFlags/INCSDIR/INCSDIR0}
  # '';

  headersOnly = true;

  MK_HESIOD = "yes";

  meta.platforms = lib.platforms.openbsd;
}
