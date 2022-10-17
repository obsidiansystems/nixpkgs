{ pkgs, haskellLib }:

with haskellLib;

let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
in

self: super: rec {

  llvmPackages = pkgs.lib.dontRecurseIntoAttrs self.ghc.llvmPackages;

  # Aeson 1.5.6.0 is easier on 8.6.5
  aeson = self.callHackage "aeson" "1.5.6.0" {};
  hashable-time = self.callHackage "hashable-time" "0.2.1" {};
  time-compat = dontCheck (self.callHackage "time-compat" "1.9.5" {});
  http2 = self.callHackage "http2" "3.0.2" {};
  http-date = dontCheck super.http-date;

  # Disable GHC 8.6.x core libraries.
  array = null;
  base = null;
  binary = null;
  bytestring = null;
  Cabal = null;
  containers = null;
  deepseq = null;
  directory = null;
  filepath = null;
  ghc-boot = null;
  ghc-boot-th = null;
  ghc-compact = null;
  ghc-heap = null;
  ghc-prim = null;
  ghci = null;
  haskeline = null;
  hpc = null;
  integer-gmp = null;
  libiserv = null;
  mtl = null;
  parsec = null;
  pretty = null;
  process = null;
  rts = null;
  stm = null;
  template-haskell = null;
  # GHC only builds terminfo if it is a native compiler
  terminfo = if pkgs.stdenv.hostPlatform == pkgs.stdenv.buildPlatform then null else self.terminfo_0_4_1_5;
  text = null;
  time = null;
  transformers = null;
  unix = null;
  # GHC only bundles the xhtml library if haddock is enabled, check if this is
  # still the case when updating: https://gitlab.haskell.org/ghc/ghc/-/blob/0198841877f6f04269d6050892b98b5c3807ce4c/ghc.mk#L463
  xhtml = if self.ghc.hasHaddock or true then null else self.xhtml_3000_2_2_1;

  # Needs Cabal 3.0.x.
  jailbreak-cabal = super.jailbreak-cabal.override { Cabal = self.Cabal_3_2_1_0; };
  Cabal-syntax = super.Cabal-syntax.override {
    Cabal = self.Cabal_3_2_1_0;
  };
  # https://github.com/tibbe/unordered-containers/issues/214
  unordered-containers = dontCheck super.unordered-containers;

  basement = super.callHackage "basement" "0.0.11" {};
  text-metrics = self.callHackage "text-metrics" "0.3.0" {};
  ghc-lib-parser = super.callHackage "ghc-lib-parser" "8.10.7.20220219" {};
  ghc-lib-parser-ex = addBuildDepend ghc-lib-parser (self.callHackage "ghc-lib-parser-ex" "8.10.0.24" { });
  stylish-haskell = doJailbreak (self.callHackage "stylish-haskell" "0.12.2.0" {});
  hlint = super.callHackage "hlint" "3.2.8" {};
  colour = haskellLib.overrideCabal (drv: {
    doCheck = false;
    testHaskellDepends = [];
  }) (super.callHackage "colour" "2.3.5" {});
  mono-traversable = self.callHackage "mono-traversable" "1.0.15.1" { };
  
  foundation = self.callHackage "foundation" "0.0.25" { };

  # Test suite does not compile.
  data-clist = doJailbreak super.data-clist; # won't cope with QuickCheck 2.12.x
  dates = doJailbreak super.dates; # base >=4.9 && <4.12
  Diff = dontCheck super.Diff;
  equivalence = dontCheck super.equivalence; # test suite doesn't compile https://github.com/pa-ba/equivalence/issues/5
  HaTeX = doJailbreak super.HaTeX; # containers >=0.4 && <0.6 is too tight; https://github.com/Daniel-Diaz/HaTeX/issues/126
  hpc-coveralls = doJailbreak super.hpc-coveralls; # https://github.com/guillaume-nargeot/hpc-coveralls/issues/82
  http-api-data = doJailbreak super.http-api-data;
  persistent-sqlite = dontCheck super.persistent-sqlite;
  system-fileio = dontCheck super.system-fileio; # avoid dependency on broken "patience"
  unicode-transforms = dontCheck super.unicode-transforms;
  wl-pprint-extras = doJailbreak super.wl-pprint-extras; # containers >=0.4 && <0.6 is too tight; https://github.com/ekmett/wl-pprint-extras/issues/17
  RSA = dontCheck super.RSA; # https://github.com/GaloisInc/RSA/issues/14
  monad-par = dontCheck super.monad-par; # https://github.com/simonmar/monad-par/issues/66
  github = dontCheck super.github; # hspec upper bound exceeded; https://github.com/phadej/github/pull/341
  binary-orphans = dontCheck super.binary-orphans; # tasty upper bound exceeded; https://github.com/phadej/binary-orphans/commit/8ce857226595dd520236ff4c51fa1a45d8387b33
  rebase = doJailbreak super.rebase; # time ==1.9.* is too low

  # https://github.com/jgm/skylighting/issues/55
  skylighting-core = dontCheck super.skylighting-core;

  # Break out of "yaml >=0.10.4.0 && <0.11": https://github.com/commercialhaskell/stack/issues/4485
  stack = doJailbreak super.stack;

  # Newer versions don't compile.
  resolv = self.resolv_0_1_1_2;

  # cabal2nix needs the latest version of Cabal, and the one
  # hackage-db uses must match, so take the latest
  cabal2nix = super.cabal2nix.overrideScope (self: super: { Cabal = self.Cabal_3_2_1_0; });

  # cabal2spec needs a recent version of Cabal
  cabal2spec = super.cabal2spec.overrideScope (self: super: { Cabal = self.Cabal_3_2_1_0; });

  # https://github.com/pikajude/stylish-cabal/issues/12
  stylish-cabal = doDistribute (markUnbroken (super.stylish-cabal.override { haddock-library = self.haddock-library_1_7_0; }));
  haddock-library_1_7_0 = dontCheck super.haddock-library_1_7_0;

  # ghc versions prior to 8.8.x needs additional dependency to compile successfully.

  # This became a core library in ghc 8.10., so we don‘t have an "exception" attribute anymore.
  exceptions = super.exceptions_0_10_5;

  # Older compilers need the latest ghc-lib to build this package.
  hls-hlint-plugin = addBuildDepend self.ghc-lib super.hls-hlint-plugin;

  # vector 0.12.2 indroduced doctest checks that don‘t work on older compilers
  vector = dontCheck super.vector;

  mmorph = super.mmorph_1_1_3;

  # https://github.com/haskellari/time-compat/issues/23
  #time-compat = dontCheck super.time-compat;

  mime-string = disableOptimization super.mime-string;

  # https://github.com/fpco/inline-c/issues/127 (recommend to upgrade to Nixpkgs GHC >=9.0)
  inline-c-cpp = (if isDarwin then dontCheck else x: x) super.inline-c-cpp;
}
