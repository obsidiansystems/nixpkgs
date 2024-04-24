{ lib, mkDerivation
, bsdSetupHook
, buildPackages
}:
mkDerivation {
  path = "include";

  extraPaths = [
    # "contrib/libc-vis"
    # "etc/mtree/BSD.include.dist"
    "sys"
  ];

  nativeBuildInputs =  [
    bsdSetupHook
    # makeMinimal
    buildPackages.netbsd.install
    # mandoc groff rsync rpcgen

    # HACK use NetBSD's for now
    buildPackages.netbsd.mtree
    buildPackages.netbsd.makeMinimal
  ];

  # patches = [
  #   ./no-perms-BSD.include.dist.patch
  # ];

  postPatch = ''
    find "$BSDSRCDIR" -name Makefile -exec \
      sed -i -E \
        -e 's_/usr/include_''${INCSDIR}_' \
        {} \;
  '';

  makeFlags = [
    "RPCGEN_CPP=${buildPackages.stdenv.cc.cc}/bin/cpp"
  ];

  # multiple header dirs, see above
  # postConfigure = ''
  #   makeFlags=''${makeFlags/INCSDIR/INCSDIR0}
  # '';

  headersOnly = true;

  MK_HESIOD = "yes";

  meta.platforms = lib.platforms.openbsd;
}
