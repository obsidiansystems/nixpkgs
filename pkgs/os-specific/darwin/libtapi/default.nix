{ lib, stdenv, fetchFromGitHub, cmake, python3, clang_6 }:

stdenv.mkDerivation {
  name = "libtapi";

  src =
    if stdenv.hostPlatform != stdenv.targetPlatform then
      fetchFromGitHub {
        owner = "tpoechtrager";
        repo = "apple-libtapi";
        rev = "3cb307764cc5f1856c8a23bbdf3eb49dfc6bea48";
        sha256 = "1zb10p6xkls8x7wsdwgy9c0v16z97rfkgidii9ffq5rfczgvrhjh";
      }
    else fetchFromGitHub {
      owner = "tpoechtrager";
      repo = "apple-libtapi";
      rev = "e56673694db395e25b31808b4fbb9a7005e6875f";
      sha256 = "1lnl1af9sszp9wxfk0wljrpdmwcx83j0w5c0y4qw4pqrdkdgwks7";
    };

  nativeBuildInputs = [ cmake python3 ];

  buildInputs = [ clang_6.cc ];

  preConfigure = ''
    cd src/llvm
  '';

  cmakeFlags = [ "-DLLVM_INCLUDE_TESTS=OFF" ];

  buildFlags = [ "libtapi" ];

  installTargets = [ "install-libtapi" "install-tapi-headers"];

  meta = with lib; {
    license = licenses.apsl20;
    maintainers = with maintainers; [ matthewbauer ];
  };

}
