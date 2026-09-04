# The toolchain a bootstrapping stage was handed by the stage before it.
#
# There are a few simple rules on deps that apply to the vast majority of
# packages: packages used at build-time are native, packages used at run-time
# are foreign, a run-time dep of a build-time dep is a transitive build-time
# dep. The overall principle is that a run-time dep is a same-stage dep, while a
# build-time dep is a previous-stage dep; a package should never depend on a
# future stage.
#
# Compilers and their wrappers are the glaring exception, because a wrapper
# injects dependencies into the artifacts the tool produces, and those belong to
# a later stage than the tool itself. `pkgs/top-level/build-wrappers.nix`, from
# the 2016 "Sane cross-compiling through bootstrapping" work, resolved this by
# reaching *forward* into `__targetPackages`. This file is that idea turned
# around: rather than each stage assembling a toolchain for its successors, a
# stage reaches *back* for the one it was given. The dependency then runs the
# same direction as every other build-time dep, so there is no future stage to
# name, and no `targetPackages` or `targetPlatform` involved.
#
# Bootstrapping logic overrides these with an overlay wherever the defaults
# don't apply --- the impure native stages, for instance, have to supply
# `nativeTools` wrappers.
{
  lib,

  # The previous stage. Everything here comes from it: these are tools that run
  # on our build platform and produce code for our host platform, so the stage
  # that builds them is the one before us.
  buildPackages,

  # Our own host platform, which the previous stage would have had to call
  # `targetPlatform`, and our own libc, which it would have had to reach forward
  # for as `targetPackages.libc`.
  hostPlatform,
  libc,
  preLibcHeaders,
  threads,

  # Our build platform, which is the previous stage's host platform.
  buildPlatform,

  # The toolchain package sets of *this* stage. Each already reaches back a
  # stage for its own `_tools`, so selecting among them here does not reach
  # back again.
  llvmPackages,
  gccNGPackages,
  zig,
  aroccPackages,

  # This set itself, taken from the package set rather than through a `rec`, so
  # that an overlay overriding one entry is seen by the others.
  tools,
}:

let
  # Shadowed by the `libc` argument of `wrapBintoolsWith`.
  libcDefault = libc;

  # One switch, not one per rung. Each toolchain package set exposes the same
  # `_tools` shape --- see `llvmPackages`, `gccNGPackages` and `zig` --- so the
  # selection happens once and every rung comes from the winner. Previously
  # `cc`, `stdenvNoLibs` and `stdenvNoLibc` each carried their own copy of this
  # chain, and they could drift.
  #
  # LLVM's own `clang` already picks `systemLibcxxClang` on Darwin, so Darwin
  # does not need an arm of its own here.
  toolchain =
    let
      # Prebuilt SDK toolchains, and platforms with no C compiler at all, come
      # as a single wrapped `cc` with no rungs below it.
      only = cc: {
        inherit cc;
        cc-unwrapped = cc.cc or cc;
        ccNoLibc = cc;
        ccNoLibs = cc;
      };
    in
    if hostPlatform.useiOSPrebuilt or false then
      only buildPackages.darwin.iosSdkPkgs.clang
    else if hostPlatform.useAndroidPrebuilt or false then
      only buildPackages."androidndkPkgs_${hostPlatform.androidNdkVersion}".clang
    # Need to use `throw` so tryEval for splicing works, ugh. Using `null` or
    # skipping the attribute would cause an eval failure `tryEval` wouldn't
    # catch, wrecking accessing previous stages when there is a C compiler and
    # everything should be fine.
    else if hostPlatform.isGhcjs then
      only (throw "no C compiler provided for this platform")
    else if hostPlatform.isDarwin || hostPlatform.useLLVM or false then
      llvmPackages._tools
    else if hostPlatform.useZig or false then
      zig._tools
    else if hostPlatform.useGccNG or false then
      gccNGPackages._tools
    else if hostPlatform.useArocc or false then
      aroccPackages._tools
    else
      gccToolchain;

  # Monolithic GCC. Unlike LLVM and the GCC-NG set it cannot express the two
  # reduced rungs separately, so `gccCrossLibcStdenv`'s compiler serves both.
  gccToolchain = rec {
    cc-unwrapped = buildPackages.gcc-unwrapped;
    cc = tools.wrapCC cc-unwrapped;
    ccNoLibc = tools.gccWithoutTargetLibc;
    ccNoLibs = ccNoLibc;
  };

in

{
  inherit (tools.gccVersioned)
    gcc13
    gcc14
    gcc15
    gcc16
    ;
  inherit (tools.gnatVersioned)
    gnat13
    gnat14
    gnat15
    gnat16
    ;
  inherit (tools.gnatBootstrapVersioned)
    gnat-bootstrap13
    gnat-bootstrap14
    gnat-bootstrap15
    gnat-bootstrap16
    ;
  inherit (tools.gccgoVersioned)
    gccgo13
    gccgo14
    gccgo15
    gccgo16
    ;
  inherit (tools.gfortranVersioned)
    gfortran13
    gfortran14
    gfortran15
    gfortran16
    ;

  # The wrappers themselves. Moving these one stage forward --- into the stage
  # that consumes the compiler, rather than the stage that built it --- is the
  # point of this file. A wrapper injects run-time deps into the artifacts its
  # tool produces; wrapped here, those deps (`libc`, `libcxx`) are simply
  # present in this stage, so nothing has to reach forward for them.
  #
  # The derivation is still built by the previous stage, via
  # `buildPackages.callPackage`: the wrapper is a script that runs on our build
  # platform, and it is `callPackage`, not the `stdenvNoCC` argument, that
  # decides where a wrapper's own dependencies come from.
  wrapCCWith =
    {
      cc,
      # The bintools this stage was handed, the same ones `stdenv.cc` links with.
      bintools ? tools.bintools,
      libc ? bintools.libc,
      # libc++ from the default LLVM version is bound at the top level, but we
      # want the C++ library to be explicitly chosen by the caller, and null by
      # default.
      libcxx ? null,
      extraPackages ? lib.optional (cc.isGNU or false && hostPlatform.isMinGW) threads.package,
      nixSupport ? { },
      ...
    }@extraArgs:
    buildPackages.callPackage ../build-support/cc-wrapper (
      let
        self = {
          nativeTools = hostPlatform == buildPlatform && buildPackages.stdenv.cc.nativeTools or false;
          nativeLibc = hostPlatform == buildPlatform && buildPackages.stdenv.cc.nativeLibc or false;
          nativePrefix = buildPackages.stdenv.cc.nativePrefix or "";
          noLibc = !self.nativeLibc && (self.libc == null);

          isGNU = cc.isGNU or false;
          isClang = cc.isClang or false;
          isArocc = cc.isArocc or false;
          isZig = cc.isZig or false;

          inherit
            cc
            bintools
            libc
            libcxx
            extraPackages
            nixSupport
            ;
        }
        // extraArgs;
      in
      self
    );

  wrapCC = cc: tools.wrapCCWith { inherit cc; };

  wrapBintoolsWith =
    {
      bintools,
      libc ? libcDefault,
      ...
    }@extraArgs:
    buildPackages.callPackage ../build-support/bintools-wrapper (
      let
        self = {
          nativeTools = hostPlatform == buildPlatform && buildPackages.stdenv.cc.nativeTools or false;
          nativeLibc = hostPlatform == buildPlatform && buildPackages.stdenv.cc.nativeLibc or false;
          nativePrefix = buildPackages.stdenv.cc.nativePrefix or "";

          noLibc = (self.libc == null);

          inherit bintools libc;
        }
        // extraArgs;
      in
      self
    );

  bintools-unwrapped =
    let
      inherit (hostPlatform) linker;
    in
    if linker == "lld" then
      buildPackages.llvmPackages.bintools-unwrapped
    else if linker == "cctools" then
      buildPackages.darwin.binutils-unwrapped
    else if linker == "bfd" then
      buildPackages.binutils-unwrapped
    else if linker == "gold" then
      buildPackages.binutils-unwrapped.override { enableGoldDefault = true; }
    else
      null;

  # The wrapping happens here, rather than the wrappers being inherited
  # ready-made from `buildPackages`, so that the choice belongs to the stage
  # that consumes it, and so that the libc is simply named rather than reached
  # forward for as `targetPackages.libc`.
  bintoolsNoLibc = tools.wrapBintoolsWith {
    bintools = tools.bintools-unwrapped;
    libc = preLibcHeaders;
  };

  # The bintools this stage was handed, wrapped here against this stage's
  # libc. A bootstrapping stage overrides this with the wrapper the bootstrap
  # made, which is then what `stdenv.cc` links with; every default below
  # takes it, so `gcc15`, `llvmPackages.clang` and the rest link with the same
  # bintools as `stdenv.cc`.
  bintools = tools.wrapBintoolsWith {
    bintools = tools.bintools-unwrapped;
    inherit libc;
  };

  # GNU binutils by name, whatever linker the platform selects: the `binutils`
  # names have always meant GNU, even where `bintools` is LLVM's. A
  # bootstrapping stage that wants the one it was handed overrides `binutils`
  # here, as it does `bintools`.
  binutils = tools.wrapBintoolsWith {
    bintools = buildPackages.binutils-unwrapped;
    inherit libc;
  };

  binutilsNoLibc = tools.wrapBintoolsWith {
    bintools = buildPackages.binutils-unwrapped;
    libc = preLibcHeaders;
  };

  binutils_nogold = lib.lowPrio (
    tools.wrapBintoolsWith {
      bintools = buildPackages.binutils-unwrapped.override { enableGold = false; };
      inherit libc;
    }
  );

  inherit (toolchain)
    cc
    cc-unwrapped
    ccNoLibc
    ccNoLibs
    ;

  # The wrapped compilers this stage uses. `all-packages.nix` now only builds
  # the unwrapped ones; wrapping them is this stage's job, which is what lets
  # the wrapper see our libc rather than reaching forward for it.
  #
  # `gcc-unwrapped` in the previous stage already targets our host platform, so
  # this is a plain re-wrap, not a re-selection.
  gccVersioned = tools.wrapVersioned "gcc" { };

  # The GCC-derived compilers come in one flavour per GCC major version, each
  # built by the previous stage as `<prefix><version>-unwrapped`. Wrap them
  # all the same way; `extra` is for wrapper arguments a family needs.
  wrapVersioned =
    prefix: extra:
    lib.listToAttrs (
      map (
        v:
        let
          n = "${prefix}${lib.replaceStrings [ "." ] [ "" ] v}";
        in
        # Versioned wrappers are low priority, as they always were; the
        # unwrapped compilers carry no priority of their own.
        lib.nameValuePair n (
          lib.lowPrio (
            tools.wrapCCWith (
              {
                cc = buildPackages."${n}-unwrapped";
              }
              // extra
            )
          )
        )
      ) (import ../development/compilers/gcc/versions.nix).allMajorVersions
    );

  gnatVersioned = tools.wrapVersioned "gnat" { };
  gnatBootstrapVersioned = tools.wrapVersioned "gnat-bootstrap" { isAlireGNAT = true; };
  gccgoVersioned = tools.wrapVersioned "gccgo" { };
  gfortranVersioned = tools.wrapVersioned "gfortran" { };

  gcc_debug = lib.lowPrio (
    tools.wrapCCWith {
      cc = buildPackages."gcc_debug-unwrapped";
    }
  );

  # Alternative linkers, wrapped here so the `-wrapper` sees this stage's
  # target prefix (which the previous stage could only reach through
  # `targetPackages.stdenv.cc.bintools`).
  mold = tools.wrapBintoolsWith {
    bintools = buildPackages.mold-unwrapped;
    extraBuildCommands = ''
      wrap ${tools.bintools.targetPrefix}ld.mold ${../build-support/bintools-wrapper/ld-wrapper.sh} ${buildPackages.mold-unwrapped}/bin/ld.mold
      wrap ${tools.bintools.targetPrefix}mold ${../build-support/bintools-wrapper/ld-wrapper.sh} ${buildPackages.mold-unwrapped}/bin/mold
    '';
  };

  wild =
    let
      ldWrapper = ../build-support/bintools-wrapper/ld-wrapper.sh;
      # NOTE: the old definition wrapped `buildPackages.wild-unwrapped` as seen
      # from the *previous* stage (two stages back) and used that stage's own
      # `stdenv.cc.bintools.targetPrefix`, i.e. the build platform's prefix.
      # Natively that is all the same thing; this wraps the previous stage's
      # binary with this stage's prefix, like `mold`.
      wild-unwrapped = buildPackages.wild-unwrapped;
    in
    tools.wrapBintoolsWith {
      bintools = wild-unwrapped;
      extraBuildCommands = ''
        wrap wild ${ldWrapper} ${lib.getExe wild-unwrapped}
        wrap ld.wild ${ldWrapper} ${lib.getExe wild-unwrapped}
        wrap ${tools.bintools.targetPrefix}ld.wild ${ldWrapper} ${lib.getExe wild-unwrapped}
        wrap ${tools.bintools.targetPrefix}ld ${ldWrapper} ${lib.getExe wild-unwrapped}
      '';
    };

  # Monolithic GCC's "no target libc" rung: the GCC used to build libc for a
  # platform. It is built against the *target's* no-libc binutils (a cross
  # compiler genuinely needs them), which is the one forward reach this stage
  # still makes for it; the wrapping, against our own pre-libc headers, is here.
  gccWithoutTargetLibc =
    (tools.wrapCCWith {
      cc = buildPackages."gccWithoutTargetLibc-unwrapped";
      bintools = tools.binutilsNoLibc;
      libc = tools.binutilsNoLibc.libc;
      extraPackages = [ ];
    }).overrideAttrs
      (prevAttrs: {
        meta = prevAttrs.meta // {
          badPlatforms =
            (prevAttrs.meta.badPlatforms or [ ])
            # This stage is native iff the previous stage's target was its host.
            ++ lib.optionals (hostPlatform == buildPlatform) [ buildPlatform.system ];
        };
      });

  # distcc masquerade: a compiler that forwards to a distcc-driven real one.
  distccWrapper = lib.makeOverridable (
    {
      extraConfig ? "",
    }:
    tools.wrapCC (buildPackages.distcc.links extraConfig)
  ) { };

  # Multilib: a GCC re-wrapped against `glibc_multi`, so it can produce both
  # 32- and 64-bit code. Takes the wrapped compiler to re-wrap.
  wrapCCMulti =
    cc:
    let
      # Binutils with glibc multi
      bintools = cc.bintools.override {
        libc = buildPackages.glibc_multi;
      };
    in
    lib.lowPrio (
      tools.wrapCCWith {
        cc = cc.cc.override {
          stdenv = buildPackages.overrideCC buildPackages.stdenv (
            tools.wrapCCWith {
              cc = cc.cc;
              inherit bintools;
              libc = buildPackages.glibc_multi;
            }
          );
          profiledCompiler = false;
          enableMultilib = true;
        };
        libc = buildPackages.glibc_multi;
        inherit bintools;
        extraBuildCommands = ''
          echo "dontMoveLib64=1" >> $out/nix-support/setup-hook
        '';
      }
    );

  gcc_multi = tools.wrapCCMulti tools.cc;

  # Multilib clang: an override of the wrapped clang, not a fresh wrap. The
  # two GCCs it borrows libraries from are the ones the previous stage links
  # with (natively that is what `gcc` and `pkgsi686Linux.gcc` were).
  wrapClangMulti =
    clang:
    buildPackages.callPackage ../development/compilers/llvm/multi.nix {
      inherit clang;
      gcc32 = buildPackages.pkgsi686Linux.stdenv.cc;
      gcc64 = buildPackages.stdenv.cc;
    };

  clang_multi = tools.wrapClangMulti llvmPackages._tools.cc;

  # The unversioned Go frontend follows the default `gcc`, which the bootstrap
  # re-injects, so it gets its own entry rather than a versioned one.
  gccgo = tools.wrapCCWith {
    cc = buildPackages.gccgo-unwrapped;
  };

  # Likewise the unversioned Fortran frontend.
  gfortran = tools.wrapCCWith {
    cc = buildPackages.gfortran-unwrapped;
  };
}
