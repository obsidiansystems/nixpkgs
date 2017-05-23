# The Nixpkgs CC is not directly usable, since it doesn't know where
# the C library and standard header files are. Therefore the compiler
# produced by that package cannot be installed directly in a user
# environment and used from the command line. So we use a wrapper
# script that sets up the right environment variables so that the
# compiler and the linker just "work".

{ name ? "", stdenv, nativeTools, noLibc ? false, nativeLibc, nativePrefix ? ""
, cc ? null, libc ? null, binutils ? null, coreutils ? null, shell ? stdenv.shell
, zlib ? null, extraPackages ? [], extraBuildCommands ? ""
, dyld ? null # TODO: should this be a setup-hook on dyld?
, isGNU ? false, isClang ? cc.isClang or false, gnugrep ? null
, hostPlatform, targetPlatform
}:

with stdenv.lib;

assert nativeTools -> nativePrefix != "";
assert !nativeTools ->
  cc != null && binutils != null && coreutils != null && gnugrep != null;
assert !(nativeLibc && noLibc);
assert (noLibc || nativeLibc) == (libc == null);

# For ghdl (the vhdl language provider to gcc) we need zlib in the wrapper.
assert cc.langVhdl or false -> zlib != null;

let
  # Prefix for binaries. Customarily ends with a dash separator.
  #
  # TODO(@Ericson2314) Make unconditional, or optional but always true by
  # default.
  prefix = stdenv.lib.optionalString (targetPlatform != hostPlatform)
                                     (targetPlatform.config + "-");

  ccVersion = (builtins.parseDrvName cc.name).version;
  ccName = (builtins.parseDrvName cc.name).name;

  libc_bin = if libc == null then null else getBin libc;
  libc_dev = if libc == null then null else getDev libc;
  libc_lib = if libc == null then null else getLib libc;
  cc_solib = getLib cc;
  binutils_bin = if nativeTools then "" else getBin binutils;
  # The wrapper scripts use 'cat' and 'grep', so we may need coreutils.
  coreutils_bin = if nativeTools then "" else getBin coreutils;
in

stdenv.mkDerivation {
  name = prefix
    + (if name != "" then name else "${ccName}-wrapper")
    + (stdenv.lib.optionalString (cc != null && ccVersion != "") "-${ccVersion}");

  preferLocalBuild = true;

  inherit cc shell libc_bin libc_dev libc_lib binutils_bin coreutils_bin;
  gnugrep_bin = if nativeTools then "" else gnugrep;

  passthru = {
    inherit libc nativeTools nativeLibc nativePrefix isGNU isClang
            prefix;

    emacsBufferSetup = pkgs: ''
      ; We should handle propagation here too
      (mapc (lambda (arg)
        (when (file-directory-p (concat arg "/include"))
          (setenv "NIX_CFLAGS_COMPILE" (concat (getenv "NIX_CFLAGS_COMPILE") " -isystem " arg "/include")))
        (when (file-directory-p (concat arg "/lib"))
          (setenv "NIX_LDFLAGS" (concat (getenv "NIX_LDFLAGS") " -L" arg "/lib")))
        (when (file-directory-p (concat arg "/lib64"))
          (setenv "NIX_LDFLAGS" (concat (getenv "NIX_LDFLAGS") " -L" arg "/lib64")))) '(${concatStringsSep " " (map (pkg: "\"${pkg}\"") pkgs)}))
    '';
  };

  buildCommand =
    ''
      mkdir -p $out/bin $out/nix-support

      wrap() {
        local dst="$1"
        local wrapper="$2"
        export prog="$3"
        substituteAll "$wrapper" "$out/bin/$dst"
        chmod +x "$out/bin/$dst"
      }
    ''

    + optionalString (libc != null) (if (!targetPlatform.isDarwin) then ''
      dynamicLinker="${libc_lib}/lib/$dynamicLinker"
      echo $dynamicLinker > $out/nix-support/dynamic-linker

      if [ -e ${libc_lib}/lib/32/ld-linux.so.2 ]; then
        echo ${libc_lib}/lib/32/ld-linux.so.2 > $out/nix-support/dynamic-linker-m32
      fi

      # The dynamic linker is passed in `ldflagsBefore' to allow
      # explicit overrides of the dynamic linker by callers to gcc/ld
      # (the *last* value counts, so ours should come first).
      echo "-dynamic-linker" $dynamicLinker > $out/nix-support/libc-ldflags-before
    '' else ''
      echo $dynamicLinker > $out/nix-support/dynamic-linker

      echo "export LD_DYLD_PATH=\"$dynamicLinker\"" >> $out/nix-support/setup-hook
    '')

    + optionalString (libc != null) ''
      # The "-B${libc_lib}/lib/" flag is a quick hack to force gcc to link
      # against the crt1.o from our own glibc, rather than the one in
      # /usr/lib.  (This is only an issue when using an `impure'
      # compiler/linker, i.e., one that searches /usr/lib and so on.)
      #
      # Unfortunately, setting -B appears to override the default search
      # path. Thus, the gcc-specific "../includes-fixed" directory is
      # now longer searched and glibc's <limits.h> header fails to
      # compile, because it uses "#include_next <limits.h>" to find the
      # limits.h file in ../includes-fixed. To remedy the problem,
      # another -idirafter is necessary to add that directory again.
      echo "-B${libc_lib}/lib/ -idirafter ${libc_dev}/include -idirafter ${cc}/lib/gcc/*/*/include-fixed" > $out/nix-support/libc-cflags

      echo "-L${libc_lib}/lib" > $out/nix-support/libc-ldflags

      echo "${libc_lib}" > $out/nix-support/orig-libc
      echo "${libc_dev}" > $out/nix-support/orig-libc-dev
    ''

    + (if nativeTools then ''
      ccPath="${if targetPlatform.isDarwin then cc else nativePrefix}/bin"
      ldPath="${nativePrefix}/bin"
    '' else ''
      echo $cc > $out/nix-support/orig-cc

      # GCC shows ${cc_solib}/lib in `gcc -print-search-dirs', but not
      # ${cc_solib}/lib64 (even though it does actually search there...)..
      # This confuses libtool.  So add it to the compiler tool search
      # path explicitly.
      if [ -e "${cc_solib}/lib64" -a ! -L "${cc_solib}/lib64" ]; then
        ccLDFlags+=" -L${cc_solib}/lib64"
        ccCFlags+=" -B${cc_solib}/lib64"
      fi
      ccLDFlags+=" -L${cc_solib}/lib"
      ccCFlags+=" -B${cc_solib}/lib"

      ${optionalString cc.langVhdl or false ''
        ccLDFlags+=" -L${zlib.out}/lib"
      ''}

      # Find the gcc libraries path (may work only without multilib).
      ${optionalString cc.langAda or false ''
        basePath=`echo ${cc_solib}/lib/*/*/*`
        ccCFlags+=" -B$basePath -I$basePath/adainclude"
        gnatCFlags="-aI$basePath/adainclude -aO$basePath/adalib"
        echo "$gnatCFlags" > $out/nix-support/gnat-cflags
      ''}

      if [ -e $ccPath/clang ]; then
        # Need files like crtbegin.o from gcc
        # It's unclear if these will ever be provided by an LLVM project
        ccCFlags="$ccCFlags -B$basePath"
        ccCFlags="$ccCFlags -isystem$cc/lib/clang/$ccVersion/include"
      fi

      echo "$ccLDFlags" > $out/nix-support/cc-ldflags
      echo "$ccCFlags" > $out/nix-support/cc-cflags

      ccPath="${cc}/bin"
      ldPath="${binutils_bin}/bin"

      # Propagate the wrapped cc so that if you install the wrapper,
      # you get tools like gcov, the manpages, etc. as well (including
      # for binutils and Glibc).
      echo ${cc} ${cc.man or ""} ${binutils_bin} ${if libc == null then "" else libc_bin} > $out/nix-support/propagated-user-env-packages

      echo ${toString extraPackages} > $out/nix-support/propagated-native-build-inputs
    ''

    + optionalString (targetPlatform.isSunOS && nativePrefix != "") ''
      # Solaris needs an additional ld wrapper.
      ldPath="${nativePrefix}/bin"
      exec="$ldPath/${prefix}ld"
      wrap ld-solaris ${./ld-solaris-wrapper.sh}
    '')

    + ''
      # Create a symlink to as (the assembler).  This is useful when a
      # cc-wrapper is installed in a user environment, as it ensures that
      # the right assembler is called.
      if [ -e $ldPath/${prefix}as ]; then
        ln -s $ldPath/${prefix}as $out/bin/${prefix}as
      fi

      wrap ${prefix}ld ${./ld-wrapper.sh} ''${ld:-$ldPath/${prefix}ld}

      if [ -e ${binutils_bin}/bin/${prefix}ld.gold ]; then
        wrap ${prefix}ld.gold ${./ld-wrapper.sh} ${binutils_bin}/bin/${prefix}ld.gold
      fi

      if [ -e ${binutils_bin}/bin/ld.bfd ]; then
        wrap ${prefix}ld.bfd ${./ld-wrapper.sh} ${binutils_bin}/bin/${prefix}ld.bfd
      fi

      export real_cc=${prefix}cc
      export real_cxx=${prefix}c++
      export default_cxx_stdlib_compile="${
        if targetPlatform.isLinux && !(cc.isGNU or false)
          then "-isystem $(echo -n ${cc.gcc}/include/c++/*) -isystem $(echo -n ${cc.gcc}/include/c++/*)/$(${cc.gcc}/bin/${prefix}gcc -dumpmachine)"
          else ""
      }"

      if [ -e $ccPath/${prefix}gcc ]; then
        wrap ${prefix}gcc ${./cc-wrapper.sh} $ccPath/${prefix}gcc
        ln -s ${prefix}gcc $out/bin/${prefix}cc
        export real_cc=${prefix}gcc
        export real_cxx=${prefix}g++
      elif [ -e $ccPath/clang ]; then
        wrap ${prefix}clang ${./cc-wrapper.sh} $ccPath/clang
        ln -s ${prefix}clang $out/bin/${prefix}cc
        export real_cc=clang
        export real_cxx=clang++
      fi

      if [ -e $ccPath/${prefix}g++ ]; then
        wrap ${prefix}g++ ${./cc-wrapper.sh} $ccPath/${prefix}g++
        ln -s ${prefix}g++ $out/bin/${prefix}c++
      elif [ -e $ccPath/clang++ ]; then
        wrap ${prefix}clang++ ${./cc-wrapper.sh} $ccPath/clang++
        ln -s ${prefix}clang++ $out/bin/${prefix}c++
      fi

      if [ -e $ccPath/cpp ]; then
        wrap ${prefix}cpp ${./cc-wrapper.sh} $ccPath/cpp
      fi
    ''

    + optionalString cc.langFortran or false ''
      wrap ${prefix}gfortran ${./cc-wrapper.sh} $ccPath/${prefix}gfortran
      ln -sv ${prefix}gfortran $out/bin/${prefix}g77
      ln -sv ${prefix}gfortran $out/bin/${prefix}f77
    ''

    + optionalString cc.langJava or false ''
      wrap ${prefix}gcj ${./cc-wrapper.sh} $ccPath/${prefix}gcj
    ''

    + optionalString cc.langGo or false ''
      wrap ${prefix}gccgo ${./cc-wrapper.sh} $ccPath/${prefix}gccgo
    ''

    + optionalString cc.langAda or false ''
      wrap ${prefix}gnatgcc ${./cc-wrapper.sh} $ccPath/${prefix}gnatgcc
      wrap ${prefix}gnatmake ${./gnat-wrapper.sh} $ccPath/${prefix}gnatmake
      wrap ${prefix}gnatbind ${./gnat-wrapper.sh} $ccPath/${prefix}gnatbind
      wrap ${prefix}gnatlink ${./gnatlink-wrapper.sh} $ccPath/${prefix}gnatlink
    ''

    + optionalString cc.langVhdl or false ''
      ln -s $ccPath/${prefix}ghdl $out/bin/${prefix}ghdl
    ''

    + ''
      substituteAll ${./setup-hook.sh} $out/nix-support/setup-hook.tmp
      cat $out/nix-support/setup-hook.tmp >> $out/nix-support/setup-hook
      rm $out/nix-support/setup-hook.tmp

      # some linkers on some platforms don't support specific -z flags
      hardening_unsupported_flags=""
      if [[ "$($ldPath/${prefix}ld -z now 2>&1 || true)" =~ un(recognized|known)\ option ]]; then
        hardening_unsupported_flags+=" bindnow"
      fi
      if [[ "$($ldPath/${prefix}ld -z relro 2>&1 || true)" =~ un(recognized|known)\ option ]]; then
        hardening_unsupported_flags+=" relro"
      fi

      substituteAll ${./add-flags.sh} $out/nix-support/add-flags.sh
      substituteAll ${./add-hardening.sh} $out/nix-support/add-hardening.sh
      cp -p ${./utils.sh} $out/nix-support/utils.sh
    ''
    + extraBuildCommands;

  # The dynamic linker has different names on different Linux platforms.
  #
  # TODO(1b62c9c06173f4d5e6b090e5ae0c68fa5f478faf): This is not the best way to
  # do this. I think the reference should be the style in the gcc-cross-wrapper,
  # but to keep a stable stdenv now I do this sufficient if/else.
  dynamicLinker =
    if !nativeLibc then
      (if targetPlatform.system == "i686-linux"     then "ld-linux.so.2" else
       if targetPlatform.system == "x86_64-linux"   then "ld-linux-x86-64.so.2" else
       # ARM with a wildcard, which can be "" or "-armhf".
       if targetPlatform.isArm32                    then "ld-linux*.so.3" else
       if targetPlatform.system == "aarch64-linux"  then "ld-linux-aarch64.so.1" else
       if targetPlatform.system == "powerpc-linux"  then "ld.so.1" else
       if targetPlatform.system == "mips64el-linux" then "ld.so.1" else
       if targetPlatform.system == "x86_64-darwin"  then "/usr/lib/dyld" else
       if stdenv.lib.hasSuffix "pc-gnu" targetPlatform.config then "ld.so.1" else
       abort "Don't know the name of the dynamic linker for this platform.")
    else "";

  crossAttrs = {
    shell = shell.crossDrv + shell.crossDrv.shellPath;
    libc = stdenv.ccCross.libc;
  };

  meta =
    let cc_ = if cc != null then cc else {}; in
    (if cc_ ? meta then removeAttrs cc.meta ["priority"] else {}) //
    { description =
        stdenv.lib.attrByPath ["meta" "description"] "System C compiler" cc_
        + " (wrapper script)";
    };
}
