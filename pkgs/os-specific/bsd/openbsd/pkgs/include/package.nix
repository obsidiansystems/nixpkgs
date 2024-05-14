{
  lib,
  mkDerivation,
  makeMinimal,
  bsdSetupHook,
  openbsdSetupHook,
  install,
  rpcgen,
  mtree,
  pax,
  buildPackages,
}:
mkDerivation {
  path = "include";

  extraPaths = [
    "lib"
    "sys"
  ];

  nativeBuildInputs = [
    bsdSetupHook
    install
    makeMinimal
    mtree
    openbsdSetupHook
    pax
    rpcgen
  ];

  patches = [
    # ./skip-rdirs.patch
    ./no-perms.patch
  ];

  makeFlags = [
    "RPCGEN_CPP=${buildPackages.stdenv.cc.cc}/bin/cpp"
    "-B"
  ];

  headersOnly = true;

  MK_HESIOD = "yes";

  meta.platforms = lib.platforms.openbsd;
}
