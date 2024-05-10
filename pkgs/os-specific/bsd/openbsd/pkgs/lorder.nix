{
  mkDerivation,
  bsdSetupHook,
  openbsdSetupHook,
  makeMinimal,
  install,
  # mandoc,
  # groff,
  # rsync,
}:

mkDerivation {
  path = "usr.bin/lorder";
  nativeBuildInputs = [
    bsdSetupHook
    openbsdSetupHook
    makeMinimal
    install
    # mandoc
    # groff
    # rsync
  ];
}
