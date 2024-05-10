{ lib, stdenv, mkDerivation
, bsdSetupHook, openbsdSetupHook
, makeMinimal
, install
, flex, byacc, gencat, rpcgen
, lorder
, csu
, include
, ctags
, tsort
, llvmPackages
}:

mkDerivation rec {
  pname = "libc";
  path = "lib/libc";
  extraPaths = [
    "lib/csu/os-note-elf.h"
    "sys/arch"

    "lib/libm"
    "lib/libpthread"
    "lib/librpcsvc"
    "lib/librpcsvc"
    "lib/librthread"
    "lib/libutil"
  ];

  patches = [
    ./libc-no-force-lcompiler_rt.patch
    ./libc-no-tags.patch
    ./disable-librebuild.patch
    ./libpthread-no-werror.patch
    # Hack around broken propogating MAKEFLAGS to submake, just inline logic
    # ./libc-msun-arch-subdir.patch

    # Don't force -lcompiler-rt, we don't actually call it that
    # ./libc-no-force--lcompiler-rt.patch

    # Fix extra include dir to get rpcsvc headers.
    # ./librpcsvc-include-subdir.patch
  ];

  nativeBuildInputs = [
    bsdSetupHook openbsdSetupHook
    makeMinimal
    install
    flex byacc gencat rpcgen
    ctags
    lorder
    tsort
  ];
  buildInputs = [ include csu ];
  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${csu}/lib"
    # "-Wno-unused-command-line-argument"
    # "-Wno-ignored-attributes"
    # "-Wno-error"
  ];

  # Suppress lld >= 16 undefined version errors
  # https://github.com/freebsd/freebsd-src/commit/2ba84b4bcdd6012e8cfbf8a0d060a4438623a638
  env.NIX_LDFLAGS = lib.optionalString (stdenv.targetPlatform.linker == "lld") "--undefined-version";

  makeFlags = [
    "STRIP=-s" # flag to install, not command
    "COMPILER_VERSION=clang"
    "LIBC_TAGS=no"
  ];

  postInstall = ''
    pushd ${include}
    find . -type d -exec mkdir -p $out/\{} \;
    find . \( -type f -o -type l \) -exec cp -pr \{} $out/\{} \;
    popd
    substituteInPlace $out/include/sys/time.h --replace "defined (_LIBC)" "true"

    pushd ${csu}
    find . -type d -exec mkdir -p $out/\{} \;
    find . \( -type f -o -type l \) -exec cp -pr \{} $out/\{} \;
    popd

    NIX_CFLAGS_COMPILE+=" -B$out/lib"
    NIX_CFLAGS_COMPILE+=" -I$out/include"
    NIX_LDFLAGS+=" -L$out/lib"

    ln -s libc.so.100.0 $out/lib/libc.so

    make -C $BSDSRCDIR/lib/libm $makeFlags
    make -C $BSDSRCDIR/lib/libm $makeFlags install

    make -C $BSDSRCDIR/lib/librthread $makeFlags
    make -C $BSDSRCDIR/lib/librthread $makeFlags install

    make -C $BSDSRCDIR/lib/librpcsvc $makeFlags
    make -C $BSDSRCDIR/lib/librpcsvc $makeFlags install

    make -C $BSDSRCDIR/lib/libutil $makeFlags
    make -C $BSDSRCDIR/lib/libutil $makeFlags install

  '';

  # ln -s ${llvmPackages.compiler-rt-no-libc}/lib/freebsd/libclang_rt.builtins-*.a $out/lib/libcompiler_rt.a

  #   sed -i -e 's| [^ ]*/libc_nonshared.a||' $out/lib/libc.so

  #   $CC -nodefaultlibs -lgcc -shared -o $out/lib/libgcc_s.so


  # '';

  meta.platforms = lib.platforms.openbsd;
}
