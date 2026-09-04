{
  lib,
  localSystem,
  config,
  overlays,
  bootStages,
}:

let
  genericStdenv = import ../generic { defaultConfig = config; };
in
bootStages
++ [
  (
    prevStage:
    let
      inherit (prevStage.stdenv) hostPlatform;
      # The compiler this stage is handed.
      cc = import ../../build-support/cc-wrapper {
        inherit lib;
        nativeTools = false;
        nativePrefix = lib.optionalString hostPlatform.isSunOS "/usr";
        nativeLibc = true;
        inherit (prevStage)
          stdenvNoCC
          binutils
          coreutils
          gnugrep
          ;
        cc = prevStage.gcc-unwrapped;
        isGNU = true;
        shell = prevStage.bash + "/bin/sh";
      };
    in
    {
    inherit config overlays;

    bootstrapOverlays = [ (self: super: { _tools = super._tools // { inherit cc; }; }) ];

    stdenvNoCC = genericStdenv {
      name = "stdenv-no-cc";
      inherit (prevStage.stdenv) buildPlatform hostPlatform targetPlatform;

      preHook = ''
        export NIX_ENFORCE_PURITY="''${NIX_ENFORCE_PURITY-1}"
        export NIX_ENFORCE_NO_NATIVE="''${NIX_ENFORCE_NO_NATIVE-1}"
        export NIX_IGNORE_LD_THROUGH_GCC=1
      '';

      initialPath = (import ../generic/common-path.nix) { pkgs = prevStage; };

      cc = null;
      hasCC = false;

      shell = prevStage.bash + "/bin/sh";

      fetchurlBoot = prevStage.stdenv.fetchurlBoot;

      overrides = self: super: {
        inherit cc;
        inherit (cc) binutils;
        inherit (prevStage)
          gzip
          bzip2
          xz
          bash
          coreutils
          diffutils
          findutils
          gawk
          gnumake
          gnused
          gnutar
          gnugrep
          gnupatch
          perl
          ;
      };
    };
    }
  )
]
