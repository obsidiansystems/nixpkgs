{ stdenv, fetchgit, bootPkgs, perl, ncurses, binutils, coreutils
, autoconf, automake, happy, alex, python3
, __targetPackages
, buildPlatform, hostPlatform, targetPlatform

  # If enabled GHC will be build with the GPL-free but slower integer-simple
  # library instead of the faster but GPLed integer-gmp library.
, enableIntegerSimple ? false
}:

let
  inherit (bootPkgs) ghc;

  version = "8.1.20170106";
  rev = "b4f2afe70ddbd0576b4eba3f82ba1ddc52e9b3bd";

  targetStdenv = __targetPackages.stdenv;
  prefix = stdenv.lib.optionalString (stdenv ? cross) "${stdenv.cross.config}-";

in stdenv.mkDerivation (rec {
  inherit version rev;
  name = "${prefix}ghc-${version}";

  src = fetchgit {
    url = "git://git.haskell.org/ghc.git";
    inherit rev;
    sha256 = "1h064nikx5srsd7qvz19f6dxvnpfjp0b3b94xs1f4nar18hzf4j0";
  };

  postPatch = "patchShebangs .";

  preConfigure = ''
    echo ${version} >VERSION
    echo ${rev} >GIT_COMMIT_ID
    ./boot
    sed -i -e 's|-isysroot /Developer/SDKs/MacOSX10.5.sdk||' configure
  '' + stdenv.lib.optionalString (!stdenv.isDarwin) ''
    export NIX_LDFLAGS="$NIX_LDFLAGS -rpath $out/lib/ghc-${version}"
  '' + stdenv.lib.optionalString stdenv.isDarwin ''
    export NIX_LDFLAGS+=" -no_dtrace_dof"
  '' + stdenv.lib.optionalString enableIntegerSimple ''
    echo "INTEGER_LIBRARY=integer-simple" > mk/build.mk
  '' + stdenv.lib.optionalString (stdenv ? cross) ''
    sed 's|#BuildFlavour  = quick-cross|BuildFlavour  = perf-cross|' mk/build.mk.sample > mk/build.mk
  '';

  nativeBuildInputs = [ ghc perl autoconf automake happy alex python3 ]
    ++ stdenv.lib.optional (stdenv ? cross) ncurses;
  buildInputs = stdenv.lib.optionals (stdenv ? cross) [
    targetStdenv.ccCross
    targetStdenv.binutilsCross
    __targetPackages.ncurses
    __targetPackages.gmp
  ] ++ stdenv.lib.optionals (stdenv ? cross && stdenv.isDarwin) [
    __targetPackages.libiconv
  ];

  enableParallelBuilding = true;

  configureFlags = [
    "CC=${targetStdenv.ccCross or stdenv.cc}/bin/${prefix}cc"
  # TODO: next rebuild remove these `--with-*` altogether
    "--with-curses-includes=${__targetPackages.ncurses.dev}/include"
    "--with-curses-libraries=${__targetPackages.ncurses.out}/lib"
  ] ++ stdenv.lib.optional (!(stdenv ? cross) && ! enableIntegerSimple) [
    "--with-gmp-includes=${__targetPackages.gmp.dev}/include"
    "--with-gmp-libraries=${__targetPackages.gmp.out}/lib"
  ] ++ stdenv.lib.optional (!(stdenv ? cross) && stdenv.isDarwin) [
    "--with-iconv-includes=${__targetPackages.libiconv}/include"
    "--with-iconv-libraries=${__targetPackages.libiconv}/lib"
  ] ++ stdenv.lib.optional (stdenv ? cross) [

    # TODO: next rebuild make these unconditional
    #"--build=x86_64-unknown-linux-gnu"#${buildPlatform.config}"
    #"--host=x86_64-unknown-linux-gnu"#${hostPlatform.config}"
    "--target=${targetPlatform.config}"
    "LD=${targetStdenv.binutilsCross or stdenv.binutils}/bin/${prefix}ld"
    "AR=${targetStdenv.binutilsCross or stdenv.binutils}/bin/${prefix}ar"
    "NM=${targetStdenv.binutilsCross or stdenv.binutils}/bin/${prefix}nm"

    "--enable-bootstrap-with-devel-snapshot"
    "--verbose"
  ];

  # required, because otherwise all symbols from HSffi.o are stripped, and
  # that in turn causes GHCi to abort
  stripDebugFlags = [ "-S" ] ++ stdenv.lib.optional (!stdenv.isDarwin) "--keep-file-symbols";

  checkTarget = "test";

  postInstall = ''
    paxmark m $out/lib/${name}/bin/{ghc,haddock}

    # Install the bash completion file.
    install -D -m 444 utils/completion/ghc.bash $out/share/bash-completion/completions/ghc

    # Patch scripts to include "readelf" and "cat" in $PATH.
    for i in "$out/bin/"*; do
      test ! -h $i || continue
      egrep --quiet '^#!' <(head -n 1 $i) || continue
      sed -i -e '2i export PATH="$PATH:${stdenv.lib.makeBinPath [ binutils coreutils ]}"' $i
    done
  '';

  passthru = {
    inherit bootPkgs;

    cc = "${targetStdenv.ccCross or stdenv.cc}/bin/${prefix}cc";
    ld = "${targetStdenv.binutilsCross or binutils}/bin/${prefix}ld";
  };

  meta = {
    homepage = "http://haskell.org/ghc";
    description = "The Glasgow Haskell Compiler";
    maintainers = with stdenv.lib.maintainers; [ marcweber andres peti ];
    inherit (ghc.meta) license platforms;
  };

  # TODO: next mass rebuild / version bump just do
  # dontSetConfigureCross = stdenv ? cross;
} // stdenv.lib.optionalAttrs (stdenv ? cross) {
  dontSetConfigureCross = true;
})
