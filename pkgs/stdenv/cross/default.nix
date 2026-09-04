{
  lib,
  localSystem,
  crossSystem,
  config,
  overlays,
  crossOverlays,
  bootStages,
}:

lib.init bootStages
++ [

  # Regular native packages
  (
    somePrevStage:
    lib.last bootStages somePrevStage
    // {
      # It's OK to change the built-time dependencies
      allowCustomOverrides = true;
    }
  )

  # Build tool Packages
  (vanillaPackages: {
    inherit config overlays;
    selfBuild = false;
    # The native stage's `stdenvNoCC`, retargeted; `stdenv` is derived from it
    # and `_tools` in `stage.nix`. The compiler is the native stage's own.
    stdenvNoCC =
      assert vanillaPackages.stdenvNoCC.buildPlatform == localSystem;
      assert vanillaPackages.stdenvNoCC.hostPlatform == localSystem;
      assert vanillaPackages.stdenvNoCC.targetPlatform == localSystem;
      vanillaPackages.stdenvNoCC.override { targetPlatform = crossSystem; };
    bootstrapOverlays = [
      (
        self: super: {
          _tools =
            super._tools
            // {
              inherit (vanillaPackages._tools) cc bintools;
            }
            // lib.optionalAttrs (vanillaPackages._tools ? sdk) {
              inherit (vanillaPackages._tools) sdk;
            };
        }
      )
    ];
    # It's OK to change the built-time dependencies
    allowCustomOverrides = true;
  })

  # Run Packages
  (
    buildPackages:
    let
      adaptStdenv = if crossSystem.isStatic then buildPackages.stdenvAdapters.makeStatic else lib.id;
      stdenvNoCC = adaptStdenv (
        buildPackages.stdenv.override (old: rec {
          buildPlatform = localSystem;
          hostPlatform = crossSystem;
          targetPlatform = crossSystem;

          # Prior overrides are surely not valid as packages built with this run on
          # a different platform, and so are disabled.
          overrides = _: _: { };
          extraBuildInputs = [ ]; # Old ones run on wrong platform
          allowedRequisites = null;

          cc = null;
          hasCC = false;

          extraNativeBuildInputs =
            old.extraNativeBuildInputs
            ++ lib.optionals (hostPlatform.isLinux && !buildPlatform.isLinux) [ buildPackages.patchelf ]
            ++ lib.optional (
              let
                f =
                  p:
                  !p.isx86
                  || builtins.elem p.libc [
                    "musl"
                    "wasilibc"
                    "relibc"
                  ]
                  || p.isiOS
                  || p.isGenode;
              in
              f hostPlatform && !(f buildPlatform)
            ) buildPackages.updateAutotoolsGnuConfigScriptsHook
            ++ lib.optional (
              hostPlatform.isCygwin && !buildPlatform.isCygwin
            ) buildPackages.cygwin.cygwinDllLinkHook;
        })
      );
    in
    {
      inherit config;
      overlays = overlays ++ crossOverlays;
      selfBuild = false;
      inherit stdenvNoCC;
      # The compiler is whatever `stage-tools.nix` selects for this host
      # platform --- that selection used to live here --- so `_tools` only has
      # to add what the selection cannot know: on Darwin the SDK is part of
      # the toolchain, and `stdenv` needs it alongside the compiler.
      bootstrapOverlays = [
        (
          self: super: {
            _tools = super._tools // lib.optionalAttrs crossSystem.isDarwin { sdk = self.apple-sdk; };
          }
        )
      ];
    }
    // lib.optionalAttrs (config ? replaceCrossStdenv) {
      # `replaceCrossStdenv` takes and returns a whole stdenv, so it cannot be
      # expressed as a toolchain; it stays on the deprecated `stdenv` argument,
      # with the base built the way it used to be.
      stdenv =
        let
          inherit (stdenvNoCC) hostPlatform targetPlatform;
          baseStdenv = stdenvNoCC.override {
            extraBuildInputs = lib.optionals hostPlatform.isDarwin [
              buildPackages.targetPackages.apple-sdk
            ];
            hasCC = !targetPlatform.isGhcjs;
            cc = buildPackages.targetPackages._tools.cc;
          };
        in
        config.replaceCrossStdenv { inherit buildPackages baseStdenv; };
    }
  )

]
