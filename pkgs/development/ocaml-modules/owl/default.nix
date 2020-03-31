{ stdenv, buildDunePackage, fetchFromGitHub, alcotest
, eigen, stdio, stdlib-shims, openblas, blas, lapack, owl-base
}:

assert (!blas.is64bit) && (!lapack.is64bit);
assert blas.implementation == "openblas" && lapack.implementation == "openblas";

buildDunePackage rec {
  pname = "owl";

  inherit (owl-base) version src meta;

  checkInputs = [ alcotest ];
  propagatedBuildInputs = [ eigen stdio stdlib-shims openblas owl-base ];

  doCheck = !stdenv.isDarwin;  # https://github.com/owlbarn/owl/issues/462
}
