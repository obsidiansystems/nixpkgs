{ stdenv, fetchFromGitHub, libusb1 }:

stdenv.mkDerivation rec {
  name = "btchip-c-api-${version}";
  version = "head";

  src = fetchFromGitHub {
    owner = "LedgerHQ";
    repo = "btchip-c-api";
    rev = "da3ff515efe8ebd8ea770deb15805e812cbcc140";
    sha256 = "1gjwhzxw2m1hn75ibyv0ngxm1p4jrrf6ly0hf36hn1x7gpvh662v";
  };

  buildInputs = [ libusb1 ];

  installPhase = ''
    mkdir -p "$out"
    cp -r ./bin ./utils ./commands "$out"
  '';

  makefile = "Makefile.libusb";
}
