{ stdenv, fetchurl, cmake, gfortran, cudatoolkit, libpthreadstubs, lapack, blas, fetchpatch
, cudaCapabilities ? ["3.5" "5.0" "5.2" "6.0" "6.1" "7.0"]
}:

with stdenv.lib;

let version = "2.5.3";

in stdenv.mkDerivation {
  pname = "magma";
  inherit version;
  src = fetchurl {
    url = "https://icl.cs.utk.edu/projectsfiles/magma/downloads/magma-${version}.tar.gz";
    sha256 = "1xjy3irdx0w1zyhvn4x47zni5fwsh6z97xd4yqldz8zrm5lx40n6";
    name = "magma-${version}.tar.gz";
  };

  patches = optionals (versionAtLeast (getVersion cudatoolkit) "11") [
    ./disable-sparse.patch
    (fetchpatch {
      url = "https://raw.githubusercontent.com/zasdfgbnm/builder/6f6767ee1ede6f5e8c37958e3521ee954ec67ab9/magma/magma-cuda110/cudaPointerAttributes.patch";
      sha256 = "14vcmdw1vhrnmj7lk1ik6z492x5xvhzl81w1dw5d1zm8j9pj62pk";
    })
  ];

  buildInputs = [ gfortran cudatoolkit libpthreadstubs cmake lapack blas ];

  cmakeFlags = [
    "-DGPU_TARGET=${builtins.concatStringsSep "," (map (s: "sm_${builtins.replaceStrings ["."] [""] s}") cudaCapabilities)}"
  ];

  doCheck = false;

  preConfigure = ''
    export CC=${cudatoolkit.cc}/bin/gcc CXX=${cudatoolkit.cc}/bin/g++
  '';

  enableParallelBuilding=true;

  meta = with stdenv.lib; {
    description = "Matrix Algebra on GPU and Multicore Architectures";
    license = licenses.bsd3;
    homepage = http://icl.cs.utk.edu/magma/index.html;
    platforms = platforms.unix;
    maintainers = with maintainers; [ tbenst ];
  };

  passthru.cudatoolkit = cudatoolkit;
  passthru.mkl = if blas.implementation == "mkl" then blas.provider else null;
}
