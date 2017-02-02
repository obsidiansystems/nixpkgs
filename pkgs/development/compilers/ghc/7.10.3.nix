{ stdenv, __targetPackages
, buildPlatform, hostPlatform, targetPlatform

# build-tools
, bootPkgs, hscolour
, binutils, coreutils, fetchurl, fetchpatch, perl
, docbook_xsl, docbook_xml_dtd_45, docbook_xml_dtd_42, libxml2, libxslt
, clang ? null, gcc ? null

, libffi, libiconv ? null, ncurses

, # LLVM is conceptually a run-time-only depedendency, but for
  # non-x86, we need LLVM to bootstrap later stages, so it becomes a
  # build-time dependency too.
  llvmPackages

, # If enabled, GHC will be build with the GPL-free but slower integer-simple
  # library instead of the faster but GPLed integer-gmp library.
  enableIntegerSimple ? false, gmp ? null

, # If enabled, use -fPIC when compiling static libs.
  enableRelocatedStaticLibs ? targetPlatform != hostPlatform

, # Whether to build dynamic libs for the standard library (on the target
  # platform). Static libs are always built.
  enableShared ?
    !(targetPlatform.isDarwin
      # On iOS, dynamic linking is not supported
      && (targetPlatform.isAarch64 || targetPlatform.isArm))
}:

assert !enableIntegerSimple -> gmp != null;

let
  inherit (bootPkgs) ghc;

  # TODO(@Ericson2314) Make unconditional
  prefix = stdenv.lib.optionalString
    (targetPlatform != hostPlatform)
    "${targetPlatform.config}-";

  docFixes = fetchurl {
    url = "https://downloads.haskell.org/~ghc/7.10.3/ghc-7.10.3a.patch";
    sha256 = "1j45z4kcd3w1rzm4hapap2xc16bbh942qnzzdbdjcwqznsccznf0";
  };

  buildMK = ''
    DYNAMIC_GHC_PROGRAMS = ${if enableShared then "YES" else "NO"}
  '' + stdenv.lib.optionalString enableIntegerSimple ''
    INTEGER_LIBRARY = integer-simple
  '' + stdenv.lib.optionalString (targetPlatform != hostPlatform) ''
    BuildFlavour = perf-cross
    Stage1Only = YES
    HADDOCK_DOCS = NO
  '' + stdenv.lib.optionalString enableRelocatedStaticLibs ''
    GhcLibHcOpts += -fPIC
    GhcRtsHcOpts += -fPIC
  '';

  # Splicer will pull out correct variations
  libDeps = platform: [ ncurses libffi ]
    ++ stdenv.lib.optional (!enableIntegerSimple) gmp
    ++ stdenv.lib.optional (platform.libc == "libSystem") libiconv;

in

stdenv.mkDerivation rec {
  version = "7.10.3";
  name = "${prefix}ghc-${version}";

  src = fetchurl {
    url = "https://downloads.haskell.org/~ghc/${version}/${name}-src.tar.xz";
    sha256 = "1vsgmic8csczl62ciz51iv8nhrkm72lyhbz7p7id13y2w7fcx46g";
  };

  enableParallelBuilding = true;

  outputs = [ "out" "doc" ];

  patches = [
    docFixes
    ./relocation.patch
  ];

  preConfigure = ''
    echo -n "${buildMK}" > mk/build.mk
    sed -i -e 's|-isysroot /Developer/SDKs/MacOSX10.5.sdk||' configure
  '' + stdenv.lib.optionalString (!stdenv.isDarwin) ''
    export NIX_LDFLAGS+=" -rpath $out/lib/ghc-${version}"
  '' + stdenv.lib.optionalString stdenv.isDarwin ''
    export NIX_LDFLAGS+=" -no_dtrace_dof"
  '';

  # TODO(@Ericson2314): Always pass "--target" and always prefix.
  configurePlatforms = [ "build" "host" ]
    ++ stdenv.lib.optional (targetPlatform != hostPlatform) "target";
  # `--with` flags for libraries needed for RTS linker
  configureFlags = [
    "--datadir=$doc/share/doc/ghc"
    "--with-system-libffi"
    "--with-curses-includes=${ncurses.dev}/include" "--with-curses-libraries=${ncurses.out}/lib"
  ] ++ stdenv.lib.optional (targetPlatform == hostPlatform && ! enableIntegerSimple) [
    "--with-gmp-includes=${gmp.dev}/include" "--with-gmp-libraries=${gmp.out}/lib"
  ] ++ stdenv.lib.optional (targetPlatform == hostPlatform && hostPlatform.isDarwin) [
    "--with-iconv-includes=${libiconv}/include" "--with-iconv-libraries=${libiconv}/lib"
  ] ++ stdenv.lib.optionals (targetPlatform != hostPlatform) [
    "--enable-bootstrap-with-devel-snapshot"
  ] ++ stdenv.lib.optionals (targetPlatform.isDarwin && targetPlatform.isAarch64) [
    # fix for iOS: https://www.reddit.com/r/haskell/comments/4ttdz1/building_an_osxi386_to_iosarm64_cross_compiler/d5qvd67/
    "--disable-large-address-space"
  ];

  nativeBuildInputs = [
    ghc perl libxml2 libxslt docbook_xsl docbook_xml_dtd_45 docbook_xml_dtd_42 hscolour
  ];

  # For building runtime libs
  __depsBuildTarget =
    if hostPlatform == buildPlatform then [
      __targetPackages.stdenv.cc
    ] else assert targetPlatform == hostPlatform; [ # build != host == target
      stdenv.cc
    ];

  buildInputs = libDeps hostPlatform;

  propagatedBuildInputs = [
    (if hostPlatform == buildPlatform
     then __targetPackages.stdenv.cc
     else (if hostPlatform.isDarwin then clang else gcc))
  ] # Stringly speaking, LLVM is only needed for platforms the native
    # code generator does not support, but using it when
    # cross-compiling anywhere.]
    ++ stdenv.lib.optional (targetPlatform != hostPlatform) llvmPackages.llvm;

  __depsTargetTarget = map stdenv.lib.getDev (libDeps targetPlatform);
  __depsTargetTargetPropagated = map (stdenv.lib.getOutput "out") (libDeps targetPlatform);

  # required, because otherwise all symbols from HSffi.o are stripped, and
  # that in turn causes GHCi to abort
  stripDebugFlags = [ "-S" ] ++ stdenv.lib.optional (!targetPlatform.isDarwin) "--keep-file-symbols";

  postInstall = ''
    # Install the bash completion file.
    install -D -m 444 utils/completion/ghc.bash $out/share/bash-completion/completions/${prefix}ghc

    # Patch scripts to include "readelf" and "cat" in $PATH.
    for i in "$out/bin/"*; do
      test ! -h $i || continue
      egrep --quiet '^#!' <(head -n 1 $i) || continue
      sed -i -e '2i export PATH="$PATH:${stdenv.lib.makeBinPath [ binutils coreutils ]}"' $i
    done
  '';

  passthru = {
    inherit bootPkgs prefix;

    inherit llvmPackages;
  };

  meta = {
    homepage = http://haskell.org/ghc;
    description = "The Glasgow Haskell Compiler";
    maintainers = with stdenv.lib.maintainers; [ marcweber andres peti ];
    inherit (ghc.meta) license platforms;
  };

}
