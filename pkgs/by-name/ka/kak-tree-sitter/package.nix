{
  stdenv,
  lib,
  makeWrapper,
  symlinkJoin,
  tinycc,
  clang,
  kak-tree-sitter-unwrapped,
}:

# Tree-Sitter grammars are C programs that need to be compiled
# Use tinycc as cc when possible to reduce closure size
let cc = if (stdenv.buildPlatform.canExecute stdenv.hostPlatform) then tinycc else clang;

in symlinkJoin (finalAttrs: {
  pname = lib.replaceStrings [ "-unwrapped" ] [ "" ] kak-tree-sitter-unwrapped.pname;
  inherit (kak-tree-sitter-unwrapped) version;
  name = "${finalAttrs.pname}-${finalAttrs.version}";

  paths = [ kak-tree-sitter-unwrapped ];
  nativeBuildInputs = [ makeWrapper ];

  postBuild = ''
    mkdir -p $out/libexec/cc/bin
    ln -s ${lib.getExe cc} $out/libexec/cc/bin/cc
    wrapProgram "$out/bin/ktsctl" \
      --suffix PATH : $out/libexec/cc/bin
  '';

  inherit (kak-tree-sitter-unwrapped) meta;
})
