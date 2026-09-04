{
  lib,
  stdenv,
  targetPackages,
  makeSetupHook,
}:

makeSetupHook {
  name = "fix-darwin-dylib-names-hook";
  substitutions = { inherit ((targetPackages._tools.cc or stdenv.cc)) targetPrefix; };
  meta = {
    platforms = lib.platforms.darwin;
    license = lib.licenses.mit;
  };
} ./fix-darwin-dylib-names.sh
