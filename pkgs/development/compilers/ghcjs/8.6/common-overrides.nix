{ haskellLib }:

let inherit (haskellLib) addBuildTools appendConfigureFlag dontHaddock doJailbreak;
in self: super: {
  ghcjs = haskellLib.overrideCabal (drv: {
    configureFlags = (drv.configureFlags or []) ++ [
      "-fno-wrapper-install"
    ];
    jailbreak = true;
    doHaddock = false;
  }) super.ghcjs;
  haddock-library-ghcjs = dontHaddock super.haddock-library-ghcjs;
  system-fileio = doJailbreak super.system-fileio;
  exceptions = super.exceptions_0_10_5;
}
