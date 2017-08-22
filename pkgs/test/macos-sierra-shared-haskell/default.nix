{ lib, haskellPackages, clangStdenv, clang-sierraHack-stdenv, stdenvNoCC }:

let
  count = 400;

  libName = prefix: i: "${prefix}-fluff${toString i}";

  src2nix = self: src: self.haskellSrc2nix {
    inherit (src) name;
    inherit src;
  };

  mkOverrides = prefix: self: super: let
    sillyLibs = lib.listToAttrs (lib.genList (i: rec {
      name = libName prefix i;
      value = stdenvNoCC.mkDerivation {
        inherit name;
        buildCommand = ''
          mkdir "$out"
          cd "$out"


          cat << 'EOF' > ${name}.cabal
          name:              ${name}
          version:           0.0.0.1
          license:           MIT

          Library
            exposed-modules: Fluff_${toString i}
            build-depends:   base
          EOF


          cat << 'EOF' > Fluff_${toString i}.hs
          module Fluff_${toString i} where

          import Data.Word

          asdf_${toString i} :: Word
          asdf_${toString i} = ${toString i}
          EOF
        '';
      };
    }) count);
  in {
    mkDerivation = attrs: super.mkDerivation (attrs // {
      configureFlags = attrs.configureFlags or [] ++ [
        "--ghc-options=-pgml${(self.callPackage ({ stdenv }: stdenv) {}).cc}/bin/cc"
      ];
    });
  } // lib.mapAttrs (_: p: self.callPackage (src2nix self p) {}) (sillyLibs // {
    finalExe = stdenvNoCC.mkDerivation rec {
      name = "${prefix}-final-asdf";
      buildCommand = ''
        mkdir "$out"
        cd "$out"


        cat << 'EOF' > ${name}.cabal
        name:              ${name}
        version:           0.0.0.1
        license:           MIT

        Executable ${name}
          main-is:         Main.hs
          build-depends:   base ${toString (map (x: ", " + x) (lib.genList (libName prefix) count))}
        EOF


        cat << 'EOF' > Main.hs
        module Main where

        import Data.Word

        ${toString (lib.genList (i: "import Fluff_${toString i};") count)}

        numbers :: [Word]
        numbers = [
            ${lib.concatStringsSep ", " (lib.genList (i: "asdf_${toString i}") count)}
          ]

        main :: IO ()
        main = print $ all id $ zipWith (==) numbers [0..]
        EOF
      '';
    };
  });

  mkHp = stdenv: prefix: haskellPackages.override {
    inherit stdenv;
    overrides = mkOverrides prefix;
  };

  good = mkHp clang-sierraHack-stdenv "good";

  bad  = mkHp clangStdenv             "bad";

in stdenvNoCC.mkDerivation {
  name = "macos-sierra-shared-haskell-test";
  nativeBuildInputs = [ good.finalExe bad.finalExe ];
  # TODO(@Ericson2314): Be impure or require exact MacOS version of builder?
  buildCommand = ''
    if bad-final-asdf
    then echo "bad-final-asdf can succeed on non-sierra, OK" >&2
    else echo "bad-final-asdf should fail on sierra, OK" >&2
    fi

    # Must succeed on all supported MacOS versions
    good-final-asdf

    touch $out
  '';
  meta.platforms = lib.platforms.darwin;
}
