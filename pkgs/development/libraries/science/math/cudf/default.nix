{ stdenv, lib, runCommand
, fetchFromGitHub, cmake, addOpenGLRunpath
, zlib, boost, cudatoolkit
, gtest
, arrow-cpp
}:

stdenv.mkDerivation rec {
  pname = "cudf";
  version = "0.18.1";

  src = fetchFromGitHub {
    owner = "rapidsai";
    repo = "cudf";
    rev = "999be56c805bcdca93ce818c1646468aed82d2c4";
    sha256 = "11amkd4wlvyrw4af22q5qabdgwavczag1cvnl610cihgm2zhi2k5";
  };

  patches = [
    (runCommand "de-vendor.patch" {
      cudaPath = cudatoolkit;
      jitifySrc = fetchFromGitHub {
        owner = "rapidsai";
        repo = "jitify";
        rev = "e3f867027c1d9603b5a677795900465b9fac9cb8";
        sha256 = "1bvslsbbzjwyff8mzxb3qr9lnbzv12l4i8wfpfimki96wrma75l9";
      };
    } ''
      substituteAll ${./de-vendor.patch} "$out"
    '')
  ];

  postPatch = ''
    cd cpp
  '';

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
    zlib boost cudatoolkit
    (arrow-cpp.override { cudaSupport = true; })
  ] ++ lib.optional doCheck gtest;

  meta = with lib; {
    description = "cuDF - GPU DataFrames";
    homepage = "https://rapids.ai/";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    maintainers = with maintainers; [ bhipple ];
  };
}
