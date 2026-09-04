# The `splicedPackages' package set, and its use by `callPackage`
#
# The `buildPackages` pkg set is a new concept, and the vast majority package
# expression (the other *.nix files) are not designed with it in mind. This
# presents us with a problem with how to get the right version (build-time vs
# run-time) of a package to a consumer that isn't used to thinking so cleverly.
#
# The solution is to splice the package sets together as we do below, so every
# `callPackage`d expression in fact gets both versions. Each derivation (and
# each derivation's outputs) consists of the run-time version, augmented with
# a `__spliced.buildHost` field for the build-time version, and
# `__spliced.hostTarget` field for the run-time version.
#
# For performance reasons, rather than uniformally splice in all cases, we only
# do so when `pkgs` and `buildPackages` are distinct. The `actuallySplice`
# parameter there the boolean value of that equality check.
lib: pkgs: actuallySplice:

let
  inherit (lib.customisation) mapCrossIndex renameCrossIndexFrom;
  inherit (lib) mapAttrs;

  # `defaultIndex` names the input whose values are the ones a consumer gets
  # when it does not go through `__spliced`: `hostTarget` for packages, and
  # `buildHost` for `_tools` (see `shiftTools`).
  spliceReal = spliceRealFrom "hostTarget";
  spliceRealFrom =
    defaultIndex: inputs:
    let
      mash =
        # Other pkgs sets
        inputs.buildBuild
        // inputs.buildTarget
        // inputs.hostHost
        // inputs.targetTarget
        # The same pkgs sets one probably intends
        // inputs.buildHost
        // inputs.hostTarget
        // inputs.${defaultIndex};
      merge =
        name: defaultValue:
        let
          # `or {}` is for the non-derivation attsert splicing case, where `{}` is the identity.
          value' = mapCrossIndex (x: x.${name} or { }) inputs;

          augmentedValue = defaultValue // {
            __spliced = lib.filterAttrs (k: v: inputs.${k} ? ${name}) value';
          };
          # Get the set of outputs of a derivation. If one derivation fails to
          # evaluate we don't want to diverge the entire splice, so we fall back
          # on {}
          tryGetOutputs =
            value0:
            let
              inherit (builtins.tryEval value0) success value;
            in
            getOutputs (lib.optionalAttrs success value);
          getOutputs =
            value: lib.genAttrs (value.outputs or (lib.optional (value ? out) "out")) (output: value.${output});
          outputNames = defaultValue.outputs or (lib.optional (defaultValue ? out) "out");
          outputSplice = spliceRealFrom defaultIndex (
            mapCrossIndex tryGetOutputs value' // { ${defaultIndex} = getOutputs value'.${defaultIndex}; }
          );
        in
        # The derivation along with its outputs, which we recur
        # on to splice them together.
        if lib.isDerivation defaultValue then
          augmentedValue // lib.genAttrs outputNames (out: outputSplice.${out})
        else if lib.isAttrs defaultValue then
          spliceRealFrom defaultIndex value'
        else
          # Don't be fancy about non-derivations. But we could have used used
          # `__functor__` for functions instead.
          defaultValue;
    in
    mapAttrs merge mash;

  # Splices the sets, with `_tools` off by one from everything else. A set's `_tools` is the
  # toolchain it was *handed*: it runs on the set's build platform and targets
  # the set's host platform. So the toolchain that "runs on build, targets
  # host" --- what a `nativeBuildInputs` entry needs, the `buildHost` slot ---
  # is `pkgsHostTarget._tools`, i.e. our own, and the one that "runs on host,
  # targets target" (`hostTarget`) is `pkgsTargetTarget._tools`. The final
  # stage has no `pkgsTargetTarget._tools`; the splice then falls back to the
  # `buildHost` one. This applies to every set spliced this way, so scopes
  # like `llvmPackages` get the same treatment for their own `_tools`.
  shiftTools =
    inputs:
    let
      without = mapAttrs (_: set: removeAttrs set [ "_tools" ]) inputs;
      tools = {
        buildBuild = inputs.buildHost._tools or { };
        buildHost = inputs.hostTarget._tools or { };
        hostTarget = inputs.targetTarget._tools or { };
        buildTarget = { };
        hostHost = { };
        targetTarget = { };
      };
    in
    spliceReal without
    // lib.optionalAttrs (inputs.hostTarget ? _tools) {
      # A consumer that reads `_tools.cc` directly, rather than through the
      # splicer, gets *this* stage's toolchain --- what `stdenv.cc` is --- so
      # the default is the `buildHost` slot, not `hostTarget`.
      _tools = spliceRealFrom "buildHost" tools;
    };

  splicePackages =
    {
      pkgsBuildBuild,
      pkgsBuildHost,
      pkgsBuildTarget,
      pkgsHostHost,
      pkgsHostTarget,
      pkgsTargetTarget,
    }@args:
    if actuallySplice then shiftTools (renameCrossIndexFrom "pkgs" args) else pkgsHostTarget;

  splicedPackages =
    splicePackages {
      inherit (pkgs)
        pkgsBuildBuild
        pkgsBuildHost
        pkgsBuildTarget
        pkgsHostHost
        pkgsHostTarget
        pkgsTargetTarget
        ;
    }
    // {
      # These should never be spliced under any circumstances
      inherit (pkgs)
        pkgsBuildBuild
        pkgsBuildHost
        pkgsBuildTarget
        pkgsHostHost
        pkgsHostTarget
        pkgsTargetTarget
        buildPackages
        pkgs
        targetPackages
        ;
    };

  pkgsForCall = if actuallySplice then splicedPackages else pkgs;

in

{
  inherit splicePackages;

  # We use `callPackage' to be able to omit function arguments that can be
  # obtained from `pkgs` or `buildPackages`.
  # Use `newScope' for sets of packages in `pkgs' (see e.g. `gnome' below).
  callPackage = pkgs.newScope { };

  callPackages = lib.callPackagesWith pkgsForCall;

  newScope = extra: lib.callPackageWith (pkgsForCall // extra);

  # `pkgs._tools` is this stage's toolchain, unspliced: bootstrapping plumbing
  # passes its entries into wrappers and dependency lists as plain
  # derivations, and a spliced one would have the splicer swap in the next
  # stage's. A package that takes `_tools` as an argument gets the spliced
  # one from `pkgsForCall` above.
  pkgs =
    if actuallySplice then
      splicedPackages
      // {
        inherit (pkgs) _tools;
        recurseForDerivations = false;
      }
    else
      pkgs;

  # prefill 2 fields of the function for convenience
  makeScopeWithSplicing = lib.makeScopeWithSplicing splicePackages pkgs.newScope;
  makeScopeWithSplicing' = lib.makeScopeWithSplicing' {
    inherit splicePackages;
    inherit (pkgs) newScope;
  };

  # generate 'otherSplices' for 'makeScopeWithSplicing'
  generateSplicesForMkScope =
    attrs:
    let
      split =
        X:
        [ X ]
        ++ (
          if builtins.isList attrs then
            attrs
          else if builtins.isString attrs then
            lib.splitString "." attrs
          else
            throw "generateSplicesForMkScope must be passed a list of string or string"
        );
      bad = throw "attribute should be found";
    in
    {
      selfBuildBuild = lib.attrByPath (split "pkgsBuildBuild") bad pkgs;
      selfBuildHost = lib.attrByPath (split "pkgsBuildHost") bad pkgs;
      selfBuildTarget = lib.attrByPath (split "pkgsBuildTarget") bad pkgs;
      selfHostHost = lib.attrByPath (split "pkgsHostHost") bad pkgs;
      selfHostTarget = lib.attrByPath (split "pkgsHostTarget") bad pkgs;
      selfTargetTarget = lib.attrByPath (split "pkgsTargetTarget") { } pkgs;
    };

  # Haskell package sets need this because they reimplement their own
  # `newScope`.
  __splicedPackages =
    if actuallySplice then splicedPackages // { recurseForDerivations = false; } else pkgs;
}
