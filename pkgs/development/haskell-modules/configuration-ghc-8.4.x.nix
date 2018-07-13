{ pkgs, haskellLib }:

with haskellLib;

self: super: {

  # This compiler version needs llvm 5.x.
  llvmPackages = pkgs.llvmPackages_5;

  # Disable GHC 8.4.x core libraries.
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
  ghc-prim = null;
  ghci = null;
  haskeline = null;
  hpc = null;

  # A few things for hspec*:
  #
  #   1. Break cycles for test
  #
  #   2. https://github.com/hspec/hspec/pull/355 The buildTool will be properly
  #      cabal2nixed when run on the patched cabal file.
  hspec = let
    breakCycles = super.hspec_2_5_3.override { stringbuilder = dontCheck self.stringbuilder; };
  in addTestToolDepend breakCycles self.hspec-meta;
  hspec-core = let
    breakCycles = super.hspec-core_2_5_3.override { silently = dontCheck self.silently; temporary = dontCheck self.temporary; };
  in addTestToolDepend breakCycles self.hspec-meta;
  hspec-discover = addTestToolDepend super.hspec-discover_2_5_3 self.hspec-meta;
  hspec-smallcheck = addTestToolDepend self.hspec-smallcheck_0_5_2 self.hspec-meta;

  integer-gmp = null;
  mtl = null;
  parsec = null;
  pretty = null;
  process = null;
  rts = null;
  stm = null;
  template-haskell = null;
  terminfo = null;
  text = null;
  time = null;
  transformers = null;
  unix = null;
  xhtml = null;

  # https://github.com/jcristovao/enclosed-exceptions/issues/12
  enclosed-exceptions = dontCheck super.enclosed-exceptions;

  # https://github.com/xmonad/xmonad/issues/155
  xmonad = addBuildDepend (appendPatch super.xmonad (pkgs.fetchpatch {
    url = https://github.com/xmonad/xmonad/pull/153/commits/c96a59fa0de2f674e60befd0f57e67b93ea7dcf6.patch;
    sha256 = "1mj3k0w8aqyy71kmc71vzhgxmr4h6i5b3sykwflzays50grjm5jp";
  })) self.semigroups;

  # https://github.com/xmonad/xmonad-contrib/issues/235
  xmonad-contrib = doJailbreak (appendPatch super.xmonad-contrib ./patches/xmonad-contrib-ghc-8.4.1-fix.patch);

  # Our xmonad claims that it's version 0.14, which is outside of this
  # package's version constraints.
  xmonad-extras = doJailbreak super.xmonad-extras;

  # https://github.com/jaor/xmobar/issues/356
  xmobar = super.xmobar.overrideScope (self: super: { hinotify = self.hinotify_0_3_9; });
  hinotify_0_3_9 = dontCheck (doJailbreak super.hinotify_0_3_9); # allow async 2.2.x

  # Older versions don't compile.
  base-compat = self.base-compat_0_10_1;
  brick = self.brick_0_37_1;
  dhall = self.dhall_1_14_0;
  dhall_1_13_0 = doJailbreak super.dhall_1_14_0;  # support ansi-terminal 0.8.x
  HaTeX = self.HaTeX_3_19_0_0;
  matrix = self.matrix_0_3_6_1;
  pandoc = self.pandoc_2_2_1;
  pandoc-types = self.pandoc-types_1_17_5_1;
  wl-pprint-text = self.wl-pprint-text_1_2_0_0;

}
