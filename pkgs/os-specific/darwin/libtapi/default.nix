{ stdenv, fetchFromGitHub
, llvm, cmake
}:


stdenv.mkDerivation {
  name = "libtapi";

  src = fetchFromGitHub {
    owner  = "tpoechtrager";
    repo   = "apple-libtapi";
    rev    = "0a11cc06d7ce2437d6a6b834a2498fceaf86398d";
    sha256 = "1n2406jlznnnpwblmcy44dpx82rvj3r09mr560mf570j9pjl1lzj";
  };

  patches = [ ./build-standalone.patch ];

  cmakeFlags = [
    "-DCMAKE_SYSTEM_NAME=Darwin"
  ];

  NIX_CFLAGS_COMPILE = [ "-std=c++11" ];

  nativeBuildInputs = [ cmake ];
  buildInputs = [ llvm ];

  outputs = [ "out" "dev" ];

  enableParallelBuilding = true;

  #postPatch = ''
  #  mv src src-old
  #  mv src-old/apple-llvm/src/projects/libtapi ./
  #  rm -rf src-old
  #  cd libtapi
  #'';
  postPatch = ''
    cd src/apple-llvm/src/projects/libtapi
  '';

  postInstall = ''
    moveToOutput include "$dev"
  '';
}
