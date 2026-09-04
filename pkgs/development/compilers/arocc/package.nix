{
  lib,
  stdenv,
  pkgs,
  targetPackages,
  overrideCC,
  zig,
  version,
  src,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "arocc";
  inherit version src;

  nativeBuildInputs = [ zig ];

  passthru = {
    inherit zig;
    isArocc = true;
  }
  // lib.optionalAttrs (pkgs.config.allowAliases && pkgs.targetPackages ? _tools) {
    # Deprecated: the wrapping now happens in `aroccPackages._tools`, in the
    # stage that consumes the compiler. These names meant what this stage hands
    # to its successor, which is that successor's `_tools`.
    wrapped = targetPackages.aroccPackages._tools.cc;
    stdenv = overrideCC stdenv targetPackages.aroccPackages._tools.cc;
  };

  meta = {
    description = "C compiler written in Zig";
    homepage = "http://aro.vexu.eu/";
    license = with lib.licenses; [
      mit
      unicode-30
    ];
    maintainers = with lib.maintainers; [ RossComputerGuy ];
    mainProgram = "arocc";
  };
})
