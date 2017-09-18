{ stdenv, __targetPackages
, buildPlatform, hostPlatform, targetPlatform
, selfPkgs, cross ? null

# build-tools
, bootPkgs, alex, happy, hscolour
, autoconf, automake, binutils, coreutils, fetchurl, perl, python3, sphinx

, libiconv ? null, ncurses

, # If enabled, GHC will be build with the GPL-free but slower integer-simple
  # library instead of the faster but GPLed integer-gmp library.
  enableIntegerSimple ? false, gmp ? null
}:

assert !enableIntegerSimple -> gmp != null;

let
  inherit (bootPkgs) ghc;

  # TODO(@Ericson2314) Make unconditional
  prefix = stdenv.lib.optionalString
    (targetPlatform != hostPlatform)
    "${targetPlatform.config}-";

  buildMK = stdenv.lib.optionalString enableIntegerSimple ''
    INTEGER_LIBRARY = integer-simple
  '' + stdenv.lib.optionalString (targetPlatform != hostPlatform) ''
    BuildFlavour = perf-cross
  '';
in
stdenv.mkDerivation (rec {
  version = "8.2.1";
  name = "${prefix}ghc-${version}";

  src = fetchurl {
    url = "https://downloads.haskell.org/~ghc/${version}/ghc-${version}-src.tar.xz";
    sha256 = "1w4k0n23b9fg8kmarqhfamzpmf91p6jcdr6xlwzfmb4df2bd9hng";
  };

  postPatch = "patchShebangs .";

  patches = [ ./ghc-gold-linker.patch ];

  preConfigure = ''
    echo -n "${buildMK}" > mk/build.mk
    sed -i -e 's|-isysroot /Developer/SDKs/MacOSX10.5.sdk||' configure
  '' + stdenv.lib.optionalString (!stdenv.isDarwin) ''
    export NIX_LDFLAGS+=" -rpath $out/lib/ghc-${version}"
  '' + stdenv.lib.optionalString stdenv.isDarwin ''
    export NIX_LDFLAGS+=" -no_dtrace_dof"
  '';

  buildInputs = [ alex autoconf automake ghc happy hscolour perl python3 sphinx ];

  enableParallelBuilding = true;

  configureFlags = [
    "CC=${stdenv.cc}/bin/cc"
    "--with-curses-includes=${ncurses.dev}/include" "--with-curses-libraries=${ncurses.out}/lib"
    "--datadir=$doc/share/doc/ghc"
  ] ++ stdenv.lib.optional (! enableIntegerSimple) [
    "--with-gmp-includes=${gmp.dev}/include" "--with-gmp-libraries=${gmp.out}/lib"
  ] ++ stdenv.lib.optional stdenv.isDarwin [
    "--with-iconv-includes=${libiconv}/include" "--with-iconv-libraries=${libiconv}/lib"
  ];

  # required, because otherwise all symbols from HSffi.o are stripped, and
  # that in turn causes GHCi to abort
  stripDebugFlags = [ "-S" ] ++ stdenv.lib.optional (!targetPlatform.isDarwin) "--keep-file-symbols";

  checkTarget = "test";

  # zsh and other shells are smart about `{ghc}` but bash isn't, and doesn't
  # treat that as a unary `{x,y,z,..}` repetition.
  postInstall = ''
    paxmark m $out/lib/${name}/bin/${if targetPlatform != hostPlatform then "ghc" else "{ghc,haddock}"}

    # Install the bash completion file.
    install -D -m 444 utils/completion/ghc.bash $out/share/bash-completion/completions/${prefix}ghc

    # Patch scripts to include "readelf" and "cat" in $PATH.
    for i in "$out/bin/"*; do
      test ! -h $i || continue
      egrep --quiet '^#!' <(head -n 1 $i) || continue
      sed -i -e '2i export PATH="$PATH:${stdenv.lib.makeBinPath [ binutils coreutils ]}"' $i
    done
  '';

  outputs = [ "out" "doc" ];

  passthru = {
    inherit bootPkgs prefix;
  } // stdenv.lib.optionalAttrs (targetPlatform != buildPlatform) {
    crossCompiler = selfPkgs.ghc.override {
      cross = targetPlatform;
      bootPkgs = selfPkgs;
    };
  };

  meta = {
    homepage = http://haskell.org/ghc;
    description = "The Glasgow Haskell Compiler";
    maintainers = with stdenv.lib.maintainers; [ marcweber andres peti ];
    inherit (ghc.meta) license platforms;
  };

} // stdenv.lib.optionalAttrs (cross != null) {
  name = "${cross.config}-ghc-${version}";

  preConfigure = ''
    sed 's|#BuildFlavour  = quick-cross|BuildFlavour  = perf-cross|' mk/build.mk.sample > mk/build.mk
  '';

  configureFlags = [
    "CC=${stdenv.ccCross}/bin/${cross.config}-cc"
    "LD=${stdenv.binutils}/bin/${cross.config}-ld"
    "AR=${stdenv.binutils}/bin/${cross.config}-ar"
    "NM=${stdenv.binutils}/bin/${cross.config}-nm"
    "RANLIB=${stdenv.binutils}/bin/${cross.config}-ranlib"
    "--target=${cross.config}"
    "--enable-bootstrap-with-devel-snapshot"
  ] ++
    # fix for iOS: https://www.reddit.com/r/haskell/comments/4ttdz1/building_an_osxi386_to_iosarm64_cross_compiler/d5qvd67/
    stdenv.lib.optional (cross.config or null == "aarch64-apple-darwin14") "--disable-large-address-space";

  dontSetConfigureCross = true;

  passthru = {
    inherit bootPkgs cross;
    cc = "${stdenv.ccCross}/bin/${cross.config}-cc";
    ld = "${stdenv.binutils}/bin/${cross.config}-ld";
  };
})
