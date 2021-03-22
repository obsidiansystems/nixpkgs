{ stdenv, lib, runCommand
, fetchFromGitHub, cmake, addOpenGLRunpath
, zlib, boost, cudatoolkit
, gtest
, arrow-cpp
}:

stdenv.mkDerivation rec {
  pname = "rmm";
  version = "0.18.0";

  src = fetchFromGitHub {
    owner = "rapidsai";
    repo = pname;
    rev = "a4ee6b7e2e9500af784c207383fdd07b8dd6088d";
    sha256 = "0rgjrcd9h5l9db9176xh99b2vnd9b7zgq31b03q7830rs1csq3kr";
  };

  outputs = [ "out" "dev" ];

  cmakeFlags = [
    "-DBUILD_TESTS=${if doCheck then "YES" else "NO"}"
  ];

  nativeBuildInputs = [
    cmake
    addOpenGLRunpath
  ];

  doCheck = false;

  buildInputs = [
    #zlib boost cudatoolkit
    #(arrow-cpp.override { cudaSupport = true; })
  ] ++ lib.optional doCheck gtest;

  meta = with lib; {
    description = "RMM: RAPIDS Memory Manager";
    homepage = "https://rapids.ai/";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    maintainers = with maintainers; [ bhipple ];
  };
}
