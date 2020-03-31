{ stdenv, lib, fetchFromGitHub, fetchpatch, ccache, cmake, ctags, swig
# data, compression
, bzip2, curl, hdf5, json_c, lzma, lzo, protobuf, snappy
# maths
<<<<<<< HEAD
, openblasCompat, eigen, nlopt, lp_solve, colpack
=======
, blas, lapack, eigen, nlopt, lp_solve, colpack, glpk
>>>>>>> 1c8aba8... treewide: use blas and lapack
# libraries
, libarchive, libxml2
# extra support
, pythonSupport ? true, pythonPackages ? null
, opencvSupport ? false, opencv ? null
}:

assert pythonSupport -> pythonPackages != null;
assert opencvSupport -> opencv != null;

<<<<<<< HEAD
=======
assert (!blas.is64bit) && (!lapack.is64bit);

let
  pname = "shogun";
  version = "6.1.4";
  rxcppVersion = "4.0.0";
  gtestVersion = "1.8.0";
  srcs = {
    toolbox = fetchFromGitHub {
      owner = pname + "-toolbox";
      repo = pname;
      rev = pname + "_" + version;
      sha256 = "38aULxK50wQ2+/ERosSpRyBmssmYSGv5aaWfWSlrSRc=";
      fetchSubmodules = true;
    };
    # we need the packed archive
    rxcpp = fetchurl {
      url = "https://github.com/Reactive-Extensions/RxCpp/archive/v${rxcppVersion}.tar.gz";
      sha256 = "0y2isr8dy2n1yjr9c5570kpc9lvdlch6jv0jvw000amwn5d3krsh";
    };
    gtest = fetchurl {
      url = "https://github.com/google/googletest/archive/release-${gtestVersion}.tar.gz";
      sha256 = "1n5p1m2m3fjrjdj752lf92f9wq3pl5cbsfrb49jqbg52ghkz99jq";
    };
  };
in

>>>>>>> 1c8aba8... treewide: use blas and lapack
stdenv.mkDerivation rec {
  pname = "shogun";
  version = "6.0.0";

  src = fetchFromGitHub {
    owner = pname + "-toolbox";
    repo = pname;
    rev = pname + "_" + version;
    sha256 = "0f2zwzvn5apvwypkfkq371xp7c5bdb4g1fwqfh8c2d57ysjxhmgf";
    fetchSubmodules = true;
  };

  patches = [
    (fetchpatch {
      name = "Fix-meta-example-parser-bug-in-parallel-builds.patch";
      url = "https://github.com/shogun-toolbox/shogun/commit/ecd6a8f11ac52748e89d27c7fab7f43c1de39f05.patch";
      sha256 = "1hrwwrj78sxhwcvgaz7n4kvh5y9snfcc4jf5xpgji5hjymnl311n";
    })
    (fetchpatch {
      url = "https://github.com/awild82/shogun/commit/365ce4c4c700736d2eec8ba6c975327a5ac2cd9b.patch";
      sha256 = "158hqv4xzw648pmjbwrhxjp7qcppqa7kvriif87gn3zdn711c49s";
    })
  ];

  CCACHE_DIR=".ccache";

  buildInputs = with lib; [
<<<<<<< HEAD
      openblasCompat bzip2 ccache cmake colpack curl ctags eigen hdf5 json_c lp_solve lzma lzo
      protobuf nlopt snappy swig (libarchive.dev) libxml2
=======
      blas lapack bzip2 cmake colpack curl ctags eigen hdf5 json_c lp_solve lzma lzo
      protobuf nlopt snappy swig (libarchive.dev) libxml2 lapack glpk
>>>>>>> 1c8aba8... treewide: use blas and lapack
    ]
    ++ optionals (pythonSupport) (with pythonPackages; [ python ply numpy ])
    ++ optional  (opencvSupport) opencv;

  cmakeFlags = with lib; []
    ++ (optional (pythonSupport) "-DPythonModular=ON")
    ++ (optional (opencvSupport) "-DOpenCV=ON")
    ;

  # Previous attempts to fix parallel builds (see patch above) were not entirely successful.
  # Sporadic build failures still exist. Dislable parallel builds for now.
  enableParallelBuilding = false;

  meta = with stdenv.lib; {
    description = "A toolbox which offers a wide range of efficient and unified machine learning methods";
    homepage = "http://shogun-toolbox.org/";
    license = licenses.gpl3;
    maintainers = with maintainers; [ edwtjo ];
  };
}
