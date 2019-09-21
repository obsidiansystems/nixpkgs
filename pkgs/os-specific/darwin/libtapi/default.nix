{ lib, stdenv, fetchFromGitHub, cmake, python }:

stdenv.mkDerivation {
  name = "libtapi";
  src = fetchFromGitHub {
    owner = "tpoechtrager";
    repo = "apple-libtapi";
    rev = "cd9885b97fdff92cc41e886bba4a404c42fdf71b";
    sha256 = "1lnl1af9sszp9wxfk0wljrpdmwcx83j0w5c0y4qw4pqrdkdgwks0";
  };

  nativeBuildInputs = [ cmake python ];

  preConfigure = ''
    cd src/llvm
  '';

  cmakeFlags = [ "-DLLVM_INCLUDE_TESTS=OFF" ];

  buildFlags = "libtapi";

  installTarget = "install-libtapi";

  meta = with lib; {
    license = licenses.apsl20;
    maintainers = with maintainers; [ matthewbauer ];
  };

}
