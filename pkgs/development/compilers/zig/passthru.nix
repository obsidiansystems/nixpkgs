{
  lib,
  stdenv,
  zig,
  pkgs,
  buildPackages,
  targetPackages,
  callPackage,
  overrideCC,
}:
{
  # Provided for backward compatibility, as the `zig` derivation now sets
  # setupHook.
  hook = zig;

  # What this stage provides: the unwrapped tools only. The wrapping happens in
  # `_tools`, in the stage that consumes them.
  bintools-unwrapped = callPackage ./bintools.nix { inherit zig; };
  cc-unwrapped = callPackage ./cc.nix { inherit zig; };

  # The toolchain the previous stage handed us, in the shape every toolchain set
  # shares; see `pkgs/top-level/stage-tools.nix`. Wrapped *here*, from
  # `buildPackages.zig`'s unwrapped tools, so it means the same thing as
  # `_tools` does at top level: what we were given, not what we hand on.
  #
  # Zig ships its own libc and compiler runtime, so unlike LLVM and the GCC-NG
  # set it has no reduced rungs to offer --- one `cc` serves all three, the way
  # monolithic GCC's `gccCrossLibcStdenv` has to.
  _tools =
    let
      # This stage's wrappers, built by the previous stage. Not a top-level
      # `wrapCCWith`: that is now the forward-facing alias.
      inherit (pkgs._tools) wrapCCWith wrapBintoolsWith;
      prev = buildPackages.zig;
    in
    {
      bintools-unwrapped = prev.bintools-unwrapped;
      bintools = wrapBintoolsWith { bintools = prev.bintools-unwrapped; };
      bintoolsNoLibc = zig._tools.bintools;

      cc-unwrapped = prev.cc-unwrapped;
      cc = wrapCCWith {
        cc = prev.cc-unwrapped;
        bintools = zig._tools.bintools;
        extraPackages = [ ];
        nixSupport.cc-cflags = [
          "-target"
          "${stdenv.hostPlatform.system}-${stdenv.hostPlatform.parsed.abi.name}"
        ];
      };
      ccNoLibc = zig._tools.cc;
      ccNoLibs = zig._tools.cc;
    };

  fetchDeps = callPackage ./fetcher.nix { inherit zig; };
}
// lib.optionalAttrs (pkgs.config.allowAliases && pkgs.targetPackages ? _tools) {
  # Deprecated: these names have always meant the compiler this stage hands to
  # its successor, which is exactly that successor's `_tools`. Prefer
  # `zig._tools.*` for the compiler this stage itself uses.
  bintools = targetPackages.zig._tools.bintools;
  cc = targetPackages.zig._tools.cc;
  stdenv = overrideCC stdenv targetPackages.zig._tools.cc;
}
