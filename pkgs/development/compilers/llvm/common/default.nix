{
  pkgs,
  targetPackages,
  lib,
  stdenv,
  preLibcHeaders,
  fetchFromGitHub,
  overrideCC,
  makeScopeWithSplicing',
  otherSplices,
  # The previous stage's counterpart of this set, whose unwrapped compiler and
  # binutils `_tools` wraps. By default that is the set of the same name in
  # `buildPackages`; a set made with `.override` from a different source (a
  # fork like ROCm's) has no such counterpart by name and passes its own.
  buildLlvmPackages ? otherSplices.selfBuildHost,
  # A set built from its own source (a fork like ROCm's) has no counterpart of
  # its name in the adjacent stages. When `standalone`, `_tools` wrap the
  # compiler and binutils this very set builds, and the deprecated wrapped names
  # refer to this set; that is only right when build, host and target agree.
  standalone ? false,
  splicePackages,
  # This is the default binutils, but with *this* version of LLD rather
  # than the default LLVM version's, if LLD is the choice. We use these for
  # the `useLLVM` bootstrapping below.
  bootBintoolsNoLibc,
  bootBintools,
  darwin,
  gitRelease ? null,
  officialRelease ? null,
  monorepoSrc ? null,
  version ? null,
  patchesFn ? lib.id,
  cmake,
  cmakeMinimal,
  python3,
  python3Minimal,
  # Allows passthrough to packages via newScope. This makes it possible to
  # do `(llvmPackages.override { <someLlvmDependency> = bar; }).clang` and get
  # an llvmPackages whose packages are overridden in an internally consistent way.
  ...
}@args:

assert lib.assertMsg (lib.xor (gitRelease != null) (officialRelease != null)) (
  "must specify `gitRelease` or `officialRelease`"
  + (lib.optionalString (gitRelease != null) " — not both")
);

let
  monorepoSrc' = monorepoSrc;

  metadata = rec {
    # Import releaseInfo separately to avoid infinite recursion
    inherit
      (import ./common-let.nix {
        inherit (args)
          lib
          gitRelease
          officialRelease
          version
          ;
      })
      releaseInfo
      ;
    inherit (releaseInfo) release_version version;
    inherit
      (import ./common-let.nix {
        inherit
          lib
          fetchFromGitHub
          release_version
          gitRelease
          officialRelease
          monorepoSrc'
          version
          ;
      })
      llvm_meta
      monorepoSrc
      ;
    src = monorepoSrc;
    versionDir =
      ../. + "/${if (gitRelease != null) then "git" else lib.versions.major release_version}";
    getVersionFile =
      p:
      builtins.path {
        name = baseNameOf p;
        path =
          let
            patches = args.patchesFn (import ./patches.nix);

            constraints = patches."${p}" or null;
            matchConstraint =
              {
                before ? null,
                after ? null,
                path,
              }:
              let
                check = fn: value: if value == null then true else fn release_version value;
                matchBefore = check lib.versionOlder before;
                matchAfter = check lib.versionAtLeast after;
              in
              matchBefore && matchAfter;

            patchDir =
              if constraints == null then
                metadata.versionDir
              else
                (lib.findFirst matchConstraint { path = metadata.versionDir; } constraints).path;
          in
          patchDir + ("/" + p);
      };
  };

in
makeScopeWithSplicing' {
  inherit otherSplices;
  extra = _spliced0: args // metadata // { inherit buildLlvmPackages; };
  f =
    self:
    let
      buildLlvmPackages' = if standalone then self else buildLlvmPackages;

      # FIXME: This is a tragic and unprincipled hack, but I don’t
      # know what would actually be good instead.
      newScope = scope: self.newScope ({ inherit (args) stdenv; } // scope);
      callPackage = newScope { };

      clangVersion = lib.versions.major metadata.release_version;

      bintoolsNoLibc' =
        if bootBintoolsNoLibc == null then self._tools.bintoolsNoLibc else bootBintoolsNoLibc;
      bintools' = if bootBintools == null then self._tools.bintools else bootBintools;
    in
    {
      inherit (metadata) release_version;

      libllvm = callPackage ./llvm { };

      # `llvm` historically had the binaries.  When choosing an output explicitly,
      # we need to reintroduce `outputSpecified` to get the expected behavior e.g. of lib.get*
      llvm = self.libllvm;

      tblgen = callPackage ./tblgen.nix {
        patches =
          builtins.filter
            # Crude method to drop polly patches if present, they're not needed for tblgen.
            (p: (!lib.hasInfix "-polly" p))
            self.libllvm.patches;
        clangPatches = [
          # Would take tools.libclang.patches, but this introduces a cycle due
          # to replacements depending on the llvm outpath (e.g. the LLVMgold patch).
          # So take the only patch known to be necessary.
          (metadata.getVersionFile "clang/gnu-install-dirs.patch")
        ];
      };

      libclang = callPackage ./clang { };

      clang-unwrapped = self.libclang;

      llvm-manpages = lib.lowPrio (
        self.libllvm.override {
          enableManpages = true;
          python3 = pkgs.python3; # don't use python-boot
        }
      );

      clang-manpages = lib.lowPrio (
        self.libclang.override {
          enableManpages = true;
          python3 = pkgs.python3; # don't use python-boot
        }
      );

      # Wrapper for standalone command line utilities
      clang-tools = callPackage ./clang-tools { };

      lld = callPackage ./lld { };

      lldbPlugins = lib.recurseIntoAttrs (
        lib.makeScopeWithSplicing'
          {
            inherit splicePackages newScope;
          }
          {
            otherSplices = lib.mapAttrs (_: selfSplice: selfSplice.lldbPlugins or { }) otherSplices;
            f = selfLldbPlugins: {
              llef = selfLldbPlugins.callPackage ./lldb-plugins/llef.nix { };
            };
          }
      );

      lldb = callPackage ./lldb { };

      lldb-manpages = lib.lowPrio (
        self.lldb.override {
          enableManpages = true;
          python3 = pkgs.python3; # don't use python-boot
        }
      );

      # Below, is the LLVM bootstrapping logic. It handles building a
      # fully LLVM toolchain from scratch. No GCC toolchain should be
      # pulled in. As a consequence, it is very quick to build different
      # targets provided by LLVM and we can also build for what GCC
      # doesn’t support like LLVM. Probably we should move to some other
      # file.

      bintools-unwrapped = callPackage ./bintools.nix { };

      # The toolchain the previous stage handed us, in the shape every toolchain
      # set shares; see `pkgs/top-level/stage-tools.nix`.
      #
      # All of LLVM's wrapping lives here, rather than pointing at something
      # `buildLlvmPackages` already wrapped. Wrapping in the stage that consumes
      # the compiler means the C++ library and compiler runtime we link against
      # are simply ours --- which is exactly what `targetLlvmPackages` has to
      # reach forward for --- and the platform we key on is our own
      # `hostPlatform`, not a `targetPlatform`.
      #
      # LLVM can express both reduced rungs: no compiler runtime at all, then
      # compiler runtime but no libc.
      _tools =
        let
          inherit (pkgs._tools) wrapCCWith wrapBintoolsWith;
          cc = buildLlvmPackages'.clang-unwrapped;
          bintoolsUnwrapped = buildLlvmPackages'.bintools-unwrapped;

          mkResourceRoot =
            cc:
            ''
              rsrc="$out/resource-root"
              mkdir "$rsrc"
              echo "-resource-dir=$rsrc" >> $out/nix-support/cc-cflags
            ''
            # clang standard c headers are incompatible with FreeBSD so we have to put them in -idirafter instead of -resource-dir
            # see https://github.com/freebsd/freebsd-src/commit/f382bac49b1378da3c2dd66bf721beaa16b5d471
            + (
              if stdenv.hostPlatform.isFreeBSD then
                ''
                  echo "-idirafter ${lib.getLib cc}/lib/clang/${clangVersion}/include" >> $out/nix-support/cc-cflags
                ''
              else
                ''
                  ln -s "${lib.getLib cc}/lib/clang/${clangVersion}/include" "$rsrc"
                ''
            );

          resourceRoot = mkResourceRoot cc;

          withRt = resourceRoot + ''
            ln -s "${self.compiler-rt.out}/lib" "$rsrc/lib"
            ln -s "${self.compiler-rt.out}/share" "$rsrc/share"
          '';

          withBasicRt = resourceRoot + ''
            ln -s "${self.compiler-rt-no-libc.out}/lib" "$rsrc/lib"
          '';
        in
        {
          bintools-unwrapped = bintoolsUnwrapped;

          bintoolsNoLibc = wrapBintoolsWith {
            bintools = bintoolsUnwrapped;
            libc = preLibcHeaders;
          };

          bintools = wrapBintoolsWith {
            bintools = bintoolsUnwrapped;
          };

          cc-unwrapped = cc;

          # The compiler this stage actually uses. What used to be the `clang`
          # switch, but keyed on our own platform and our own default compiler
          # rather than on the target's --- that is what
          # `targetPackages.stdenv.cc.isGNU` was for.
          cc =
            if stdenv.hostPlatform.libc == null then
              self._tools.ccNoLibc
            else if stdenv.hostPlatform.isDarwin then
              self._tools.systemLibcxxClang
            else if stdenv.hostPlatform.useLLVM or false then
              self._tools.clangUseLLVM
            else if stdenv.cc.isGNU then
              self._tools.libstdcxxClang
            else
              self._tools.libcxxClang;

          libstdcxxClang = wrapCCWith {
            inherit cc;
            # libstdcxx is taken from gcc in an ad-hoc way in cc-wrapper.
            libcxx = null;
            extraPackages = [ self.compiler-rt ];
            extraBuildCommands = withRt;
          };

          libcxxClang = wrapCCWith {
            inherit cc;
            libcxx = self.libcxx;
            extraPackages = [ self.compiler-rt ];
            extraBuildCommands = withRt;
          };

          # Darwin uses the system libc++ by default. It is its own definition so
          # that `libcxxClang` continues to use the libc++ from LLVM.
          systemLibcxxClang = wrapCCWith {
            inherit cc;
            libcxx = darwin.libcxx;
            extraPackages = [ self.compiler-rt ];
            extraBuildCommands = withRt;
          };

          clangUseLLVM = wrapCCWith {
            inherit cc;
            libcxx = self.libcxx;
            bintools = bintools';
            extraPackages = [
              self.compiler-rt
            ]
            ++ lib.optionals (!stdenv.hostPlatform.isWasm && !stdenv.hostPlatform.isFreeBSD) [
              self.libunwind
            ];
            extraBuildCommands = withRt;
            nixSupport.cc-cflags = [
              "-rtlib=compiler-rt"
              "-Wno-unused-command-line-argument"
              "-B${self.compiler-rt}/lib"
            ]
            ++ lib.optional (!stdenv.hostPlatform.isWasm) "--unwindlib=libunwind"
            ++ lib.optional (!stdenv.hostPlatform.isWasm && stdenv.hostPlatform.useLLVM or false) "-lunwind"
            ++ lib.optional stdenv.hostPlatform.isWasm "-fno-exceptions";
            nixSupport.cc-ldflags = lib.optionals (
              !stdenv.hostPlatform.isWasm && !stdenv.hostPlatform.isFreeBSD && !stdenv.hostPlatform.isDarwin
            ) [ "-L${self.libunwind}/lib" ];
          };

          # Compiler runtime but no libc.
          ccNoLibc = wrapCCWith {
            inherit cc;
            libcxx = null;
            bintools = bintoolsNoLibc';
            extraPackages = [ self.compiler-rt-no-libc ];
            extraBuildCommands = withBasicRt;
            nixSupport.cc-cflags = [
              "-rtlib=compiler-rt"
              "-B${self.compiler-rt-no-libc}/lib"
            ]
            ++ lib.optional stdenv.hostPlatform.isWasm "-fno-exceptions";
          };

          # No compiler runtime at all.
          ccNoLibs = wrapCCWith {
            inherit cc;
            libcxx = null;
            bintools = bintoolsNoLibc';
            extraPackages = [ ];
            extraBuildCommands = resourceRoot;
            # "-nostartfiles" used to be needed for pkgsLLVM, causes problems so don't include it.
            nixSupport.cc-cflags = lib.optional stdenv.hostPlatform.isWasm "-fno-exceptions";
          };

          # libc but only the basic compiler runtime.
          ccWithLibcAndBasicRt = wrapCCWith {
            inherit cc;
            libcxx = null;
            bintools = bintools';
            extraPackages = [ self.compiler-rt-no-libc ];
            extraBuildCommands = withBasicRt;
            nixSupport.cc-cflags = [
              "-rtlib=compiler-rt"
              "-B${self.compiler-rt-no-libc}/lib"
              "-nostdlib++"
            ]
            ++ lib.optional stdenv.hostPlatform.isWasm "-fno-exceptions";
          };

          # libc, the basic compiler runtime, and libc++. Used to build
          # compiler-rt.
          ccWithLibcAndBasicRtAndLibcxx = wrapCCWith {
            inherit cc;
            # Make sure to use the system libc++ on Darwin.
            libcxx = if stdenv.hostPlatform.isDarwin then darwin.libcxx else self.libcxx;
            bintools = bintools';
            extraPackages = [
              self.compiler-rt-no-libc
            ]
            ++
              lib.optionals
                (!stdenv.hostPlatform.isWasm && !stdenv.hostPlatform.isFreeBSD && !stdenv.hostPlatform.isDarwin)
                [
                  self.libunwind
                ];
            extraBuildCommands = withBasicRt;
            nixSupport.cc-cflags = [
              "-rtlib=compiler-rt"
              "-Wno-unused-command-line-argument"
              "-B${self.compiler-rt-no-libc}/lib"
            ]
            ++ lib.optional (
              !stdenv.hostPlatform.isWasm && !stdenv.hostPlatform.isFreeBSD && !stdenv.hostPlatform.isDarwin
            ) "--unwindlib=libunwind"
            ++ lib.optional (
              !stdenv.hostPlatform.isWasm
              && !stdenv.hostPlatform.isFreeBSD
              && stdenv.hostPlatform.useLLVM or false
            ) "-lunwind"
            ++ lib.optional stdenv.hostPlatform.isWasm "-fno-exceptions";
            nixSupport.cc-ldflags = lib.optionals (
              !stdenv.hostPlatform.isWasm && !stdenv.hostPlatform.isFreeBSD && !stdenv.hostPlatform.isDarwin
            ) [ "-L${self.libunwind}/lib" ];
          };

          # Fortran. Only present from LLVM 20; forcing it on an older set is
          # an error, as it was before.
          flang =
            let
              flangUnwrapped = buildLlvmPackages'.flang-unwrapped;
            in
            wrapCCWith {
              cc = flangUnwrapped;
              bintools = bintools';
              extraPackages = [ self.flang-rt ];
              extraBuildCommands = mkResourceRoot flangUnwrapped + ''
                # triplet however is not used in darwin
                PLATFORM_DIR="${if stdenv.hostPlatform.isDarwin then "darwin" else stdenv.hostPlatform.config}"
                RT_LIB_PATH="${self.flang-rt}/lib/clang/${clangVersion}/lib/$PLATFORM_DIR"
                if [ -d "$RT_LIB_PATH" ]; then
                  ln -s "$RT_LIB_PATH" "$rsrc"/lib
                  echo "-L$rsrc/lib" >> $out/nix-support/cc-ldflags
                else
                  ln -s "${self.flang-rt}/lib" "$rsrc"/lib
                  echo "-L$rsrc/lib" >> $out/nix-support/cc-ldflags
                fi
              '';
            };

          # An "oddly ordered" bootstrap rung just for Darwin.
          ccNoCompilerRtWithLibc = wrapCCWith {
            inherit cc;
            libcxx = null;
            bintools = bintools';
            extraPackages = [ ];
            extraBuildCommands = resourceRoot;
            nixSupport.cc-cflags = lib.optional stdenv.hostPlatform.isWasm "-fno-exceptions";
          };
        };

      compiler-rt-libc = callPackage ./compiler-rt (
        let
          # temp rename to avoid infinite recursion
          stdenv =
            # Darwin needs to use a bootstrap stdenv to avoid an infinite recursion when cross-compiling.
            if args.stdenv.hostPlatform.isDarwin then
              overrideCC darwin.bootstrapStdenv self._tools.ccWithLibcAndBasicRtAndLibcxx
            else if args.stdenv.hostPlatform.useLLVM or false then
              overrideCC args.stdenv self._tools.ccWithLibcAndBasicRtAndLibcxx
            else
              args.stdenv;
        in
        {
          inherit stdenv;
        }
      );

      compiler-rt-no-libc = callPackage ./compiler-rt {
        doFakeLibgcc = stdenv.hostPlatform.useLLVM or false;
        stdenv =
          # Darwin needs to use a bootstrap stdenv to avoid an infinite recursion when cross-compiling.
          if stdenv.hostPlatform.isDarwin then
            overrideCC darwin.bootstrapStdenv self._tools.ccNoLibs
          else
            overrideCC stdenv self._tools.ccNoLibs;
      };

      compiler-rt =
        if
          stdenv.hostPlatform.libc == null
          # Building the with-libc compiler-rt and WASM doesn't yet work,
          # because wasilibc doesn't provide some expected things. See
          # compiler-rt's file for further details.
          || stdenv.hostPlatform.isWasm
          # Failing `#include <term.h>` in
          # `lib/sanitizer_common/sanitizer_platform_limits_freebsd.cpp`
          # sanitizers, not sure where to get it.
          || stdenv.hostPlatform.isFreeBSD
        then
          self.compiler-rt-no-libc
        else
          self.compiler-rt-libc;

      stdenv = overrideCC stdenv self._tools.cc;

      libcxxStdenv = overrideCC stdenv self._tools.libcxxClang;

      libcxx = callPackage ./libcxx {
        stdenv =
          if stdenv.hostPlatform.isDarwin then
            overrideCC darwin.bootstrapStdenv self._tools.ccWithLibcAndBasicRt
          else
            overrideCC stdenv self._tools.ccWithLibcAndBasicRt;
      };

      libunwind = callPackage ./libunwind {
        stdenv = overrideCC stdenv self._tools.ccWithLibcAndBasicRt;
      };

      openmp = callPackage ./openmp { };

      mlir = callPackage ./mlir { };
    }
    // lib.optionalAttrs (pkgs.config.allowAliases && pkgs.targetPackages ? _tools) (
      let
        # Only the deprecated names below still reach forward; keep the binding
        # next to them rather than at the top of the file.
        targetLlvmPackages =
          if standalone || otherSplices.selfTargetTarget == { } then self else otherSplices.selfTargetTarget;
      in
      {

        # Deprecated: names kept because packages outside this file still use
        # them. All the wrapping now happens in `_tools` above; these are pointers
        # into it. They go through `targetLlvmPackages` because these names have
        # always meant the compiler this stage hands to its successor, which is
        # exactly that successor's `_tools`.
        clang = targetLlvmPackages._tools.cc;
        libstdcxxClang = targetLlvmPackages._tools.libstdcxxClang;
        libcxxClang = targetLlvmPackages._tools.libcxxClang;
        systemLibcxxClang = targetLlvmPackages._tools.systemLibcxxClang;
        clangUseLLVM = targetLlvmPackages._tools.clangUseLLVM;
        bintools = targetLlvmPackages._tools.bintools;
        bintoolsNoLibc = targetLlvmPackages._tools.bintoolsNoLibc;
        clangNoLibcNoRt = targetLlvmPackages._tools.ccNoLibs;
        clangNoLibcWithBasicRt = targetLlvmPackages._tools.ccNoLibc;
        clangWithLibcAndBasicRt = targetLlvmPackages._tools.ccWithLibcAndBasicRt;
        clangNoCompilerRtWithLibc = targetLlvmPackages._tools.ccNoCompilerRtWithLibc;
        clangNoCompilerRt = targetLlvmPackages._tools.ccNoLibs;
        clangNoLibc = targetLlvmPackages._tools.ccNoLibc;
        clangNoLibcxx = targetLlvmPackages._tools.ccWithLibcAndBasicRt;
      }
    )
    // lib.optionalAttrs (lib.versionAtLeast metadata.release_version "19") {
      bolt = callPackage ./bolt { };
    }
    // lib.optionalAttrs (lib.versionAtLeast metadata.release_version "20") (
      let
        # Standalone flang still resolves driver/option definitions via the
        # installed libclang package, so keep flang-specific driver backports
        # in a private libclang variant instead of patching the flang source
        # tree. The `-Xflang` diagnostic improvement applies to every
        # supported standalone-flang version (20+); the other two backports
        # are only needed up to LLVM 21 because upstream merged equivalent
        # behaviour into LLVM 22.
        flangDriverPatches =
          lib.optionals (lib.versionAtLeast metadata.release_version "20") [
            (metadata.getVersionFile "flang/use-xflang-in-diagnostics.patch")
          ]
          ++
            lib.optionals
              (lib.versionAtLeast metadata.release_version "20" && lib.versionOlder metadata.release_version "22")
              [
                (metadata.getVersionFile "flang/warn-on-fbuiltin-and-fno-builtin.patch")
                (metadata.getVersionFile "flang/accept-and-ignore-some-gfortran-optimization-flags.patch")
              ];
        flangLibclang =
          if flangDriverPatches == [ ] then
            self.libclang
          else
            self.libclang.override {
              extraPatches = flangDriverPatches;
            };
        flangUnwrapped = callPackage ./flang {
          libclang = flangLibclang;
        };
        # The only other place that still reaches forward.
        targetLlvmPackages =
          if standalone || otherSplices.selfTargetTarget == { } then self else otherSplices.selfTargetTarget;

        flangRt = callPackage ./flang-rt {
          buildFlang = buildLlvmPackages'.flang-unwrapped;
        };
      in
      {
        flang-unwrapped = flangUnwrapped;
        flang-rt = flangRt;
        libc-overlay = callPackage ./libc {
          isFullBuild = false;
          # Use clang due to "gnu::naked" not working on aarch64.
          # Issue: https://gcc.gnu.org/bugzilla/show_bug.cgi?id=77882
          stdenv = overrideCC stdenv self._tools.cc;
        };

        libc-full = callPackage ./libc {
          isFullBuild = true;
          # Use clang due to "gnu::naked" not working on aarch64.
          # Issue: https://gcc.gnu.org/bugzilla/show_bug.cgi?id=77882
          stdenv = overrideCC stdenv self._tools.ccNoLibs;
          # FIXME: This should almost certainly be `stdenv.hostPlatform`.
          cmake = if stdenv.targetPlatform.libc == "llvm" then cmakeMinimal else cmake;
          python3 = if stdenv.targetPlatform.libc == "llvm" then python3Minimal else python3;
        };

        libc =
          # FIXME: This should almost certainly be `stdenv.hostPlatform`.
          if stdenv.targetPlatform.libc == "llvm" then self.libc-full else self.libc-overlay;
      }
      // lib.optionalAttrs (pkgs.config.allowAliases && pkgs.targetPackages ? _tools) {
        # Deprecated, like `clang` above: the forward-facing name for the
        # wrapped Fortran compiler, which is the successor's `_tools.flang`.
        flang =
          let
            wrapped = targetLlvmPackages._tools.flang;
            tests = callPackage ./flang/tests.nix {
              flang = wrapped;
            };
          in
          wrapped
          // {
            passthru = (wrapped.passthru or { }) // {
              inherit tests;
            };
          };
      }
    );
}
