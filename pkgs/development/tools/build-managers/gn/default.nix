{ stdenv, lib, fetchgit, darwin, writeText
, ninja, python3
}:

let
  # Note: Please use the recommended version for Chromium, e.g.:
  # https://git.archlinux.org/svntogit/packages.git/tree/trunk/chromium-gn-version.sh?h=packages/gn
  rev = "5ed3c9cc67b090d5e311e4bd2aba072173e82db9";
  revNum = "1718"; # git describe HEAD --match initial-commit | cut -d- -f3
  version = "2020-03-23";
  sha256 = "00y2d35wvqmx9glaqhfb62wdgbfpwr77v0934nnvh9ks71vnsjqy";

  revShort = builtins.substring 0 7 rev;
  lastCommitPosition = writeText "last_commit_position.h" ''
    #ifndef OUT_LAST_COMMIT_POSITION_H_
    #define OUT_LAST_COMMIT_POSITION_H_

    #define LAST_COMMIT_POSITION_NUM ${revNum}
    #define LAST_COMMIT_POSITION "${revNum} (${revShort})"

    #endif  // OUT_LAST_COMMIT_POSITION_H_
  '';

in stdenv.mkDerivation {
  pname = "gn-unstable";
  inherit version;

  src = fetchgit {
    # Note: The TAR-Archives (+archive/${rev}.tar.gz) are not deterministic!
    url = "https://gn.googlesource.com/gn";
    inherit rev sha256;
  };

  nativeBuildInputs = [ ninja python3 ];
  buildInputs = lib.optionals stdenv.isDarwin (with darwin; with apple_sdk.frameworks; [
    libobjc
    cctools

    # frameworks
    ApplicationServices
    Foundation
    AppKit
  ]);

  buildPhase = ''
    python build/gen.py --no-last-commit-position
    ln -s ${lastCommitPosition} out/last_commit_position.h
    ninja -j $NIX_BUILD_CORES -C out gn
  '';

  installPhase = ''
    install -vD out/gn "$out/bin/gn"
  '';

  setupHook = ./setup-hook.sh;

  meta = with lib; {
    description = "A meta-build system that generates build files for Ninja";
    homepage = "https://gn.googlesource.com/gn";
    license = licenses.bsd3;
    platforms = platforms.unix;
    maintainers = with maintainers; [ stesie matthewbauer ];
  };
}
