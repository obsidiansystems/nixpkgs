{ stdenv, fetchgit, bootPkgs, perl, binutils, coreutils
, autoconf, automake, happy, alex, python3
, ncurses, gmp, libffi
, __targetPackages
, buildPlatform, hostPlatform, targetPlatform

, # LLVM is conceptually a run-time-only depedendency, but for
  # non-x86, we need LLVM to bootstrap later stages, so it becomes a
  # build-time dependency too.
  #
  # We generally want the latest llvm package set, which would normally be
  # `llvmPackages` on most platforms. But on Darwin, the default is the version
  # released with OSX, so we force 3.9, which is the correct version at this
  # time.
  #
  # TODO: redundancy betweeen the configuration files and this in
  # picking the appropriate LLVM version.
  llvmPackages_39

, # If enabled, GHC will be build with the GPL-free but slower integer-simple
  # library instead of the faster but GPLed integer-gmp library.
  enableIntegerSimple ? buildPlatform != targetPlatform

, # If enabled, use -fPIC when compiling static libs.
  enableRelocatedStaticLibs ? buildPlatform != targetPlatform

, # TODO: Make false by default
  useVendoredLibffi ? true

, # Whether to build dynamic libs for the standard library (on the target
  # platform). Static libs are always built.
  dynamic ? let triple = targetPlatform.config or "";
    # On iOS, dynamic linking is not supported
    in !(stdenv.lib.strings.hasPrefix "aarch64-apple-darwin" triple)
    && !(stdenv.lib.strings.hasPrefix "arm-apple-darwin" triple)
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

  llvmPackages = llvmPackages_39;

  prebuiltAndroidTarget = targetPlatform.useAndroidPrebuilt or false;

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
    sed 's|#BuildFlavour  = quick-cross|BuildFlavour  = perf-cross|' mk/build.mk.sample > mk/build.mk
    echo 'Stage1Only = YES' >> mk/build.mk
  '' + stdenv.lib.optionalString (buildPlatform != targetPlatform && dynamic) ''
    echo 'DYNAMIC_GHC_PROGRAMS = YES' >> mk/build.mk
  '' + stdenv.lib.optionalString enableRelocatedStaticLibs ''
    echo 'GhcLibHcOpts += -fPIC' >> mk/build.mk
    echo 'GhcRtsHcOpts += -fPIC' >> mk/build.mk
  '' + stdenv.lib.optionalString prebuiltAndroidTarget ''
    echo 'EXTRA_CC_OPTS += -std=gnu99' >> mk/build.mk
  '' + stdenv.lib.optionalString enableIntegerSimple ''
    echo "INTEGER_LIBRARY = integer-simple" >> mk/build.mk
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

    # Stringly speaking, LLVM is only needed for platforms the native
    # code generator does not support, but using it when
    # cross-compiling anywhere.
    llvmPackages.llvm

    ncurses.dev __targetPackages.ncurses.dev
  ] ++ stdenv.lib.optionals ((!enableIntegerSimple) && (buildPlatform != targetPlatform)) [
    gmp.dev __targetPackages.gmp.dev
  ] ++ stdenv.lib.optionals (!useVendoredLibffi) [
    libffi.dev __targetPackages.libffi.dev
  ];

  propagatedBuildInputs = stdenv.lib.optionals (buildPlatform != targetPlatform) [
    ncurses.out __targetPackages.ncurses.out
  ] ++ stdenv.lib.optionals ((!enableIntegerSimple) && (buildPlatform != targetPlatform)) [
    gmp.out __targetPackages.gmp.out
  ] ++ stdenv.lib.optionals (!useVendoredLibffi) [
    libffi.out __targetPackages.libffi.out
  ] ++ stdenv.lib.optionals (prebuiltAndroidTarget || (buildPlatform != hostPlatform && targetPlatform.libc or "" == "libsystem")) [
    __targetPackages.libiconv
  ];

  enableParallelBuilding = true;

  configureFlags = [
    "CC=${targetStdenv.cc or stdenv.cc}/bin/${prefix}cc"
  # TODO: With Cross rebuild (need to fix hooks) remove these `--with-*` altogether
  ] ++ stdenv.lib.optionals (buildPlatform == targetPlatform) [
    "--with-curses-includes=${__targetPackages.ncurses.dev}/include"
    "--with-curses-libraries=${__targetPackages.ncurses.out}/lib"
  ] ++ stdenv.lib.optionals (buildPlatform == targetPlatform && !enableIntegerSimple) [
    "--with-gmp-includes=${__targetPackages.gmp.dev}/include"
    "--with-gmp-libraries=${__targetPackages.gmp.out}/lib"
  ] ++ stdenv.lib.optionals (buildPlatform == targetPlatform && stdenv.isDarwin) [
    "--with-iconv-includes=${__targetPackages.libiconv}/include"
    "--with-iconv-libraries=${__targetPackages.libiconv}/lib"
  ] ++ stdenv.lib.optionals (buildPlatform != targetPlatform) [

    # TODO: next rebuild make these unconditional
    #"--build=x86_64-unknown-linux-gnu"#${buildPlatform.config}"
    #"--host=x86_64-unknown-linux-gnu"#${hostPlatform.config}"
    "--target=${targetPlatform.config}"

    "--enable-bootstrap-with-devel-snapshot"
    "--verbose"
    #"--with-system-libffi"
  ] ++ stdenv.lib.optionals (targetPlatform.config or "" == "aarch64-apple-darwin14") [
    # Hack for iOS
    "--disable-large-address-space"
  ];

  # required, because otherwise all symbols from HSffi.o are stripped, and
  # that in turn causes GHCi to abort
  stripDebugFlags = [ "-S" ] ++ stdenv.lib.optional (!stdenv.isDarwin) "--keep-file-symbols";

  checkTarget = "test";

  # zsh and other shells are smart about `{ghc}` but bash isn't, and doesn't
  # treat that as a unary `{x,y,z,..}` repetition.
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
} // stdenv.lib.optionalAttrs prebuiltAndroidTarget {

  # It gets confused with ncurses
  dontPatchELF = true;
  dontCrossPatchELF = true;

  # It uses the native strip on libraries too
  dontStrip = true;
  dontCrossStrip = true;

  patches = [
    ./android-patches/add-llvm-target-data-layout.patch
    #./android-patches/build-deps-extra-cc-opts.patch
    ./android-patches/unix-posix_vdisable.patch
    #./android-patches/unix-posix-files-imports.patch
    ./android-patches/enable-fPIC.patch
    ./android-patches/no-pthread-android.patch
    ./android-patches/force_CC_SUPPORTS_TLS_equal_zero.patch
    ./android-patches/undefine_MYTASK_USE_TLV_for_CC_SUPPORTS_TLS_zero.patch
    ./android-patches/force-relocation-equal-pic.patch
    ./android-patches/rts_android_log_write.patch
    ./android-patches/patch_rts_elf.patch

    ./android-patches/extra-modules-temp.patch
    ./android-patches/pthread-die-temp.patch
  ];
} // stdenv.lib.optionalAttrs (buildPlatform != targetPlatform && targetPlatform.libc or "" == "libSystem") {
  patches = [
    ./android-patches/enable-fPIC.patch
  ];
})
