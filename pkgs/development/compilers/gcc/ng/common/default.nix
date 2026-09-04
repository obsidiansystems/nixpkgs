{
  lib,
  pkgs,
  newScope,
  stdenv,
  overrideCC,
  fetchgit,
  fetchurl,
  gitRelease ? null,
  officialRelease ? null,
  monorepoSrc ? null,
  version ? null,
  patchesFn ? lib.id,
  buildGccPackages,
  targetGccPackages,
  windows,
  makeScopeWithSplicing',
  otherSplices,
  ...
}@args:

assert lib.assertMsg (lib.xor (gitRelease != null) (officialRelease != null)) (
  "must specify `gitRelease` or `officialRelease`"
  + (lib.optionalString (gitRelease != null) " — not both")
);

let
  monorepoSrc' = monorepoSrc;

  metadata = rec {
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
          fetchgit
          fetchurl
          release_version
          gitRelease
          officialRelease
          monorepoSrc'
          version
          ;
      })
      gcc_meta
      monorepoSrc
      ;
    src = monorepoSrc;
    versionDir =
      (toString ../.) + "/${if (gitRelease != null) then "git" else lib.versions.major release_version}";
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
              toString
                (
                  if constraints == null then
                    { path = metadata.versionDir; }
                  else
                    (lib.findFirst matchConstraint { path = metadata.versionDir; } constraints)
                ).path;
          in
          "${patchDir}/${p}";
      };
  };
in
makeScopeWithSplicing' {
  inherit otherSplices;
  f =
    gccPackages:
    let
      callPackage = gccPackages.newScope (args // metadata);

      # libgomp is OpenMP on top of pthreads, and will refuse to build with
      # any other threading model.
      hasLibgomp = gccPackages.libgcc.threadModel == "posix";

      libgompCflags = lib.optionals hasLibgomp [
        "-B${gccPackages.libgomp}/lib"
      ];
      libgompIncludeCflags = lib.optionals hasLibgomp [
        "-I${gccPackages.libgomp}/lib/gcc/${metadata.release_version}/include"
      ];

      # Every compiler from the threaded `libgcc-libc` onwards needs the
      # threading library's headers and import library: that is what
      # `gthr-default.h` includes and what libstdc++ and user code link
      # against. As with the runtime libraries, it is the *target* build.
      threadsPackages = lib.optional (gccPackages.threads != null) gccPackages.threads;

      # `extraPackages` only reaches builds that go through a stdenv, so name
      # the directories here too, as the runtime libraries are: otherwise the
      # wrapped compiler run by hand cannot find the `mcfgthread` header.
      threadsCflags = lib.optionals (gccPackages.threads != null) [
        "-B${gccPackages.threads}/lib"
        "-isystem ${lib.getDev gccPackages.threads}/include"
      ];

      # A gcc *configured* for a threading model links that model's library
      # through its own specs. Ours is configured independently of the runtimes
      # (see ../README.md), so the flag has to come from the wrapper instead;
      # without it libstdc++ fails to link on undefined `__MCF_gthr_*`.
      #
      # A whole `nixSupport` fragment rather than just the flag list: an empty
      # `cc-ldflags` still gets written by `cc-wrapper`, so setting the
      # attribute unconditionally would rebuild every wrapper everywhere.
      threadsNixSupport = lib.optionalAttrs ((gccPackages.threads.threadModel or null) == "mcf") {
        cc-ldflags = [ "-lmcfgthread" ];
      };
    in
    {
      # Where the libc's own threading is not the one we want, a separate
      # library supplies it: MinGW offers only `win32`, and `mcfgthreads` gives
      # `mcf`, which is the better answer on Windows. `null`, the answer
      # everywhere else, means "whatever the libc offers".
      # The model is not written down here; the package declares it, in the
      # same `passthru.threadModel` a libc uses.
      #
      # This stays out of the bootstrap cycle by itself: it is built with
      # `windows.crossThreadsStdenv`, which on `useGccNG` platforms is stage 3
      # — real libc, bootstrap single-threaded libgcc — the very compiler that
      # goes on to build the threaded `libgcc-libc`.
      threads = if stdenv.hostPlatform.isMinGW then windows.mcfgthreads else null;

      stdenv = overrideCC stdenv gccPackages._tools.gcc;

      gcc-unwrapped = callPackage ./gcc {
        # A cross compiler is built against its *target*'s binutils. This is a
        # forward reach, and the one place in this file that still has one;
        # see the note on `postStage` in `pkgs/stdenv/booter.nix`.
        bintools = pkgs.targetPackages._tools.binutils or pkgs._tools.binutils;
      };

      libiberty = callPackage ./libiberty { };
      libsanitizer = callPackage ./libsanitizer { };
      libquadmath = callPackage ./libquadmath { };

      gfortran-unwrapped = gccPackages.gcc-unwrapped.override {
        stdenv = overrideCC stdenv gccPackages._tools.gcc;
        langFortran = true;
      };




      # Stage 1 of the bootstrap chain; see ../README.md.
      #
      # No `libc` is passed: `wrapCCWith` defaults it to `bintools.libc`, and
      # `binutilsNoLibc` carries `preLibcHeaders`. That is the only place the
      # pre-libc stage is written down.

      # Built before there is a libc, and not intended for use beyond getting
      # one built. Note the two differ only by `stdenv`: which stage this is
      # follows from the compiler, never from an argument.
      libgcc-no-libc = callPackage ./libgcc {
        stdenv = overrideCC stdenv gccPackages._tools.gccNoLibgcc;
        # The bootstrap libgcc predates the threading library. Spelled out so
        # `callPackage` does not fill it in from the set's own `threads`.
        threads = null;
      };

      # The real one, built against the finished libc, so it can use that
      # libc's threads — or the separate threading library where we have asked
      # for one. This is what everything above the libc gets.
      libgcc-libc = callPackage ./libgcc {
        stdenv = overrideCC stdenv gccPackages._tools.gccWithLibcAndBasicLibgcc;
        # Spelled out for the same reason as the `null` above, and so that it
        # is this set's own answer.
        inherit (gccPackages) threads;
      };

      libgcc =
        if stdenv.hostPlatform.libc == null then gccPackages.libgcc-no-libc else gccPackages.libgcc-libc;

      # Stage 2: libgcc available, libc not yet — what compiling a libc needs.
      # `binutilsNoLibc` is what keeps the libc out, so nothing here refers to
      # a libc derivation and the cycle stays broken.

      # Freestanding libstdc++ not depending on any libc
      libstdcxx-no-libc = callPackage ./libstdcxx {
        stdenv = overrideCC stdenv gccPackages._tools.gccWithLibgccNoCxx;
        # The set's plain `libgcc` is the finished one, which is built after
        # the libc; only the bootstrap libgcc exists this early.
        libgcc = gccPackages.libgcc-no-libc;
      };


      # The toolchain the previous stage handed us, in the shape every toolchain
      # set shares; see `pkgs/top-level/stage-tools.nix`.
      #
      # All of this set's wrapping lives here. Wrapping in the stage that
      # consumes the compiler means the runtime libraries it links against ---
      # `libgcc`, `libstdcxx`, `libssp`, `libatomic`, `libgomp` --- are simply
      # ours, which is what `targetGccPackages` had to reach forward for. That
      # reach is now gone from this file except for the deprecated names below.
      #
      # Like LLVM, and unlike monolithic GCC, the split set can express both
      # reduced rungs.
      _tools =
        let
          # This stage's wrappers, built by the previous stage. NOT the `wrapCCWith`
          # argument above: that is now the forward-facing alias, which in the last
          # stage would build the wrapper *for* our host and close a cycle through
          # our own libc.
          inherit (pkgs._tools) wrapCCWith;
        in
        {
        # GCC links with GNU binutils by name, whatever the stage's own bintools
        # are (on Darwin they are cctools). On a bootstrapped linux stage that is
        # the wrapper the bootstrap handed over, which is what these rungs were
        # always built with.
        bintools-unwrapped = pkgs.buildPackages.binutils-unwrapped;
        bintools = pkgs._tools.binutils;
        bintoolsNoLibc = pkgs._tools.binutilsNoLibc;

        cc-unwrapped = buildGccPackages.gcc-unwrapped;
        cc = gccPackages._tools.gcc;
        ccNoLibc = gccPackages._tools.gccWithLibgcc;
        ccNoLibs = gccPackages._tools.gccNoLibgcc;

        gfortran = wrapCCWith {
          cc = buildGccPackages.gfortran-unwrapped;
          libcxx = gccPackages.libstdcxx;
          bintools = gccPackages._tools.bintools;
          extraPackages = [
            gccPackages.libgcc
          ]
          ++ threadsPackages;
          nixSupport = threadsNixSupport // {
            cc-cflags = [
              "-B${gccPackages.libgcc}/lib"
              "-B${gccPackages.libssp}/lib"
              "-B${gccPackages.libatomic}/lib"
            ]
            ++ libgompCflags
            ++ [
              "-B${gccPackages.libstdcxx}/lib"
              "-B${gccPackages.libgfortran}/lib/"
              # `libgfortran.spec`, which the driver reads from the directory
              # above, links `-lquadmath` unconditionally.
              "-B${gccPackages.libquadmath}/lib"
            ]
            ++ threadsCflags;
          };
        };

        gfortranNoLibgfortran = wrapCCWith {
          cc = buildGccPackages.gfortran-unwrapped;
          libcxx = gccPackages.libstdcxx;
          bintools = gccPackages._tools.bintools;
          extraPackages = [
            gccPackages.libgcc
          ]
          ++ threadsPackages;
          nixSupport = threadsNixSupport // {
            cc-cflags = [
              "-B${gccPackages.libgcc}/lib"
              "-B${gccPackages.libssp}/lib"
              "-B${gccPackages.libatomic}/lib"
            ]
            ++ libgompCflags
            ++ libgompIncludeCflags
            ++ threadsCflags;
          };
        };

        gcc = wrapCCWith {
          cc = buildGccPackages.gcc-unwrapped;
          libcxx = gccPackages.libstdcxx;
          bintools = gccPackages._tools.bintools;
          extraPackages = [
            gccPackages.libgcc
          ]
          ++ threadsPackages;
          nixSupport = threadsNixSupport // {
            cc-cflags = [
              "-B${gccPackages.libgcc}/lib"
              "-B${gccPackages.libssp}/lib"
              "-B${gccPackages.libatomic}/lib"
            ]
            ++ libgompCflags
            ++ [
              # `libcxx` above tells cc-wrapper where the C++ *headers* are; it does
              # not put the library itself on the link path for a GNU compiler. So
              # every C++ link failed with `cannot find -lstdc++` until this was
              # added, in the same style as the other runtime libraries.
              "-B${gccPackages.libstdcxx}/lib"
            ]
            ++ libgompIncludeCflags
            ++ threadsCflags;
          };
        };

        gccNoLibgcc = wrapCCWith {
          cc = buildGccPackages.gcc-unwrapped;
          libcxx = null;
          bintools = gccPackages._tools.bintoolsNoLibc;
          extraPackages = [ ];
          nixSupport.cc-cflags = [
            "-nostartfiles"
          ];
        };

        gccWithLibgccNoCxx = wrapCCWith {
          cc = buildGccPackages.gcc-unwrapped;
          libcxx = null;
          bintools = gccPackages._tools.bintoolsNoLibc;
          extraPackages = [
            gccPackages.libgcc-no-libc
          ];
          nixSupport.cc-cflags = [
            "-B${gccPackages.libgcc-no-libc}/lib"
          ];
        };

        gccWithLibgcc =
          # Cygwin's libc is in partly C++ and needs C++ headers to build.
          if stdenv.targetPlatform.isCygwin then
            wrapCCWith {
              cc = buildGccPackages.gcc-unwrapped;
              libcxx = gccPackages.libstdcxx-no-libc;
              bintools = gccPackages._tools.bintoolsNoLibc;
              extraPackages = [
                gccPackages.libgcc-no-libc
              ];
              nixSupport.cc-cflags = [
                "-B${gccPackages.libgcc-no-libc}/lib"
                # See above for why `libcxx = ...` is not enough.
                "-B${gccPackages.libstdcxx-no-libc}/lib"
              ];
            }
          else
            gccPackages._tools.gccWithLibgccNoCxx;

        # Stage 3: real libc, bootstrap libgcc still. The finished libgcc is what
        # this is about to build.

        gccWithLibcAndBasicLibgcc = wrapCCWith {
          cc = buildGccPackages.gcc-unwrapped;
          libcxx = null;
          bintools = gccPackages._tools.bintools;
          extraPackages = [
            gccPackages.libgcc-no-libc
          ];
          nixSupport.cc-cflags = [
            "-B${gccPackages.libgcc-no-libc}/lib"
          ];
        };

        gccWithLibc = wrapCCWith {
          cc = buildGccPackages.gcc-unwrapped;
          libcxx = null;
          bintools = gccPackages._tools.bintools;
          extraPackages = [
            gccPackages.libgcc
          ]
          ++ threadsPackages;
          nixSupport = threadsNixSupport // {
            cc-cflags = [
              "-B${gccPackages.libgcc}/lib"
            ]
            ++ threadsCflags;
          };
        };

        gccWithLibssp = wrapCCWith {
          cc = buildGccPackages.gcc-unwrapped;
          libcxx = null;
          bintools = gccPackages._tools.bintools;
          extraPackages = [
            gccPackages.libgcc
          ]
          ++ threadsPackages;
          nixSupport = threadsNixSupport // {
            cc-cflags = [
              "-B${gccPackages.libgcc}/lib"
              "-B${gccPackages.libssp}/lib"
            ]
            ++ threadsCflags;
          };
        };

        gccWithLibatomic = wrapCCWith {
          cc = buildGccPackages.gcc-unwrapped;
          libcxx = null;
          bintools = gccPackages._tools.bintools;
          extraPackages = [
            gccPackages.libgcc
          ]
          ++ threadsPackages;
          nixSupport = threadsNixSupport // {
            cc-cflags = [
              "-B${gccPackages.libgcc}/lib"
              "-B${gccPackages.libssp}/lib"
              "-B${gccPackages.libatomic}/lib"
            ]
            ++ threadsCflags;
          };
        };

      };



      libssp = callPackage ./libssp {
        stdenv = overrideCC stdenv gccPackages._tools.gccWithLibc;
      };


      libatomic = callPackage ./libatomic {
        stdenv = overrideCC stdenv gccPackages._tools.gccWithLibssp;
      };


      libgfortran = callPackage ./libgfortran {
        stdenv = overrideCC stdenv gccPackages._tools.gcc;
        gfortran = gccPackages._tools.gfortranNoLibgfortran;
      };

      libstdcxx = callPackage ./libstdcxx {
        stdenv = overrideCC stdenv gccPackages._tools.gccWithLibatomic;
      };

      libgomp = callPackage ./libgomp {
        stdenv = overrideCC stdenv gccPackages._tools.gccWithLibatomic;
      };
    }
    // lib.optionalAttrs (pkgs.config.allowAliases && pkgs.targetPackages ? _tools) (
      let
        # Only the deprecated names below still reach forward; keep the binding
        # next to them rather than at the top of the file.
        targetGccPackages =
          if otherSplices.selfTargetTarget == { } then gccPackages else otherSplices.selfTargetTarget;
      in
      {
        # Deprecated: names kept because packages outside this file still use
        # them. All the wrapping now happens in `_tools` above; these are
        # pointers into it. They go through `targetGccPackages` because these
        # names have always meant the compiler this stage hands to its
        # successor, which is exactly that successor's `_tools`.
        gcc = targetGccPackages._tools.gcc;
        gfortran = targetGccPackages._tools.gfortran;
        gfortranNoLibgfortran = targetGccPackages._tools.gfortranNoLibgfortran;
        gccNoLibgcc = targetGccPackages._tools.gccNoLibgcc;
        gccWithLibgccNoCxx = targetGccPackages._tools.gccWithLibgccNoCxx;
        gccWithLibgcc = targetGccPackages._tools.gccWithLibgcc;
        gccWithLibcAndBasicLibgcc = targetGccPackages._tools.gccWithLibcAndBasicLibgcc;
        gccWithLibc = targetGccPackages._tools.gccWithLibc;
        gccWithLibssp = targetGccPackages._tools.gccWithLibssp;
        gccWithLibatomic = targetGccPackages._tools.gccWithLibatomic;
      }
    );
}
