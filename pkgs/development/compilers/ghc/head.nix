{ stdenv, fetchgit, bootPkgs, perl, binutils, coreutils
, autoconf, automake, happy, alex, python3
, ncurses, gmp, libffi
, buildPackages, __targetPackages
, buildPlatform, hostPlatform, targetPlatform

, # LLVM is conceptually a run-time-only depedendency, but for
  # non-x86, we need LLVM to bootstrap later stages, so it becomes a
  # build-time dependency too.
  #
  # TODO: redundancy betweeen the configuration files and this in
  # picking the appropriate LLVM version.
  llvmPackages

  # If enabled GHC will be build with the GPL-free but slower integer-simple
  # library instead of the faster but GPLed integer-gmp library.
, enableIntegerSimple ? false
}:

let
  inherit (bootPkgs) ghc;

  version = "8.1.20170106";
  rev = "b4f2afe70ddbd0576b4eba3f82ba1ddc52e9b3bd";

  targetStdenv = __targetPackages.stdenv;
  prefix = stdenv.lib.optionalString
    (buildPlatform != targetPlatform)
    "${targetPlatform.config}-";
  underscorePrefix = stdenv.lib.optionalString
    (buildPlatform != targetPlatform)
    "${stdenv.lib.replaceStrings ["-"] ["_"] targetPlatform.config}_";

in stdenv.mkDerivation (rec {
  inherit version rev;
  name = "${prefix}ghc-${version}";

  src = fetchgit {
    url = "git://git.haskell.org/ghc.git";
    inherit rev;
    sha256 = "1h064nikx5srsd7qvz19f6dxvnpfjp0b3b94xs1f4nar18hzf4j0";
  };

  postPatch = "patchShebangs .";

  #v p dyn
  preConfigure = stdenv.lib.optionalString (buildPlatform != targetPlatform)''
    sed 's|#BuildFlavour  = quick-cross|BuildFlavour  = quick-cross|' mk/build.mk.sample > mk/build.mk
    echo 'GhcLibWays = v dyn' >> mk/build.mk
  '' + stdenv.lib.optionalString enableIntegerSimple ''
    echo "INTEGER_LIBRARY=integer-simple" >> mk/build.mk
  '' + ''
    echo ${version} >VERSION
    echo ${rev} >GIT_COMMIT_ID
    ./boot
    sed -i -e 's|-isysroot /Developer/SDKs/MacOSX10.5.sdk||' configure
  '' +
    ( if stdenv.isDarwin
      then ''
        export NIX_LDFLAGS+=" -no_dtrace_dof"
      '' else ''
        export NIX_LDFLAGS="$NIX_LDFLAGS -rpath $out/lib/ghc-${version}"
      ''); # perf-cross

  nativeBuildInputs = [
    ghc perl autoconf automake happy alex python3
  ];
  buildInputs = stdenv.lib.optionals (buildPlatform != targetPlatform) [
    targetStdenv.cc

    ncurses.out ncurses.dev
    gmp.out gmp.dev
    libffi.out libffi.dev

    __targetPackages.ncurses.out __targetPackages.ncurses.dev
    __targetPackages.gmp.out __targetPackages.gmp.dev
    __targetPackages.libffi.out __targetPackages.libffi.dev

    # Stringly speaking, LLVM is only needed for platforms the native
    # code generator does not support, but using it when
    # cross-compiling anywhere.
    #
    # Using host != target llvm is better (but probably a no-op) in
    # principle, but is currently broken.
    buildPackages.llvmPackages.llvm
  ] ++ stdenv.lib.optionals (buildPlatform != targetPlatform && stdenv.isDarwin) [
    __targetPackages.libiconv
  ];

  enableParallelBuilding = true;

  configureFlags = [
    "CC=${targetStdenv.cc or stdenv.cc}/bin/${prefix}cc"
  # TODO: next rebuild remove these `--with-*` altogether
    "--with-curses-includes=${__targetPackages.ncurses.dev}/include"
    "--with-curses-libraries=${__targetPackages.ncurses.out}/lib"
  ] ++ stdenv.lib.optional (buildPlatform == targetPlatform && ! enableIntegerSimple) [
    "--with-gmp-includes=${__targetPackages.gmp.dev}/include"
    "--with-gmp-libraries=${__targetPackages.gmp.out}/lib"
  ] ++ stdenv.lib.optional (buildPlatform == targetPlatform && stdenv.isDarwin) [
    "--with-iconv-includes=${__targetPackages.libiconv}/include"
    "--with-iconv-libraries=${__targetPackages.libiconv}/lib"
  ] ++ stdenv.lib.optional (buildPlatform != targetPlatform) [

    # TODO: next rebuild make these unconditional
    #"--build=x86_64-unknown-linux-gnu"#${buildPlatform.config}"
    #"--host=x86_64-unknown-linux-gnu"#${hostPlatform.config}"
    "--target=${targetPlatform.config}"

    "--enable-bootstrap-with-devel-snapshot"
    "--verbose"
    "--with-system-libffi"
  ];

  # required, because otherwise all symbols from HSffi.o are stripped, and
  # that in turn causes GHCi to abort
  stripDebugFlags = [ "-S" ] ++ stdenv.lib.optional (!stdenv.isDarwin) "--keep-file-symbols";

  checkTarget = "test";

  # bash is smart about `{ghc}` but sh isn't, and doesn't treat that as a unary
  # {x,y,z,..}  repetition.
  postInstall = ''
    paxmark m $out/lib/${name}/bin/${if buildPlatform != targetPlatform then "ghc" else "{ghc,haddock}"}

    # Install the bash completion file.
    install -D -m 444 utils/completion/ghc.bash $out/share/bash-completion/completions/${prefix}ghc

    # Patch scripts to include "readelf" and "cat" in $PATH.
    for i in "$out/bin/"*; do
      test ! -h $i || continue
      egrep --quiet '^#!' <(head -n 1 $i) || continue
      sed -i -e '2i export PATH="$PATH:${stdenv.lib.makeBinPath [
        # TODO always use cross
        (if stdenv.isDarwin then targetStdenv.binutilsCross or binutils else binutils)
        coreutils
      ]}"' $i
    done
  '';

  passthru = {
    inherit bootPkgs;

    inherit llvmPackages;
  };

  meta = {
    homepage = "http://haskell.org/ghc";
    description = "The Glasgow Haskell Compiler";
    maintainers = with stdenv.lib.maintainers; [ marcweber andres peti ];
    inherit (ghc.meta) license platforms;
  };

  # TODO: next mass rebuild / version bump just do
  # dontSetConfigureCross = buildPlatform != targetPlatform;
} // stdenv.lib.optionalAttrs (buildPlatform != targetPlatform) {
  # It gets confused with ncurses
  dontPatchELF = true;
})
