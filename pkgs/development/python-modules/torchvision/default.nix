{ stdenv, fetchFromGitHub, buildPythonPackage, six, pillow, torch, numpy }:

buildPythonPackage rec {
  name = "torchvision-${version}";
  version = "0.1.8";

  src = fetchFromGitHub {
    owner = "pytorch";
    repo = "vision";
    rev = "834ac30ab5f0aab6e6fd9d3b9d8782765f5e4b1b";
    sha256 = "1bgh8ryf6nlsmmvdijqxjdb67gawpqqby367208zi5nj2lwp4rzf";
  };

  buildInputs = [ pillow six ];

  propagatedBuildInputs = [
    pillow six numpy torch
  ];

  doCheck = false;

  meta = {
    description = "Datasets, Transforms and Models specific to Computer Vision";
  };
}
