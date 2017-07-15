{ stdenv, fetchurl, zlib, lib, buildPackages, buildPlatform, hostPlatform}:

stdenv.mkDerivation rec {
  name = "file-${version}";
  version = "5.31";

  src = fetchurl {
    urls = [
      "ftp://ftp.astron.com/pub/file/${name}.tar.gz"
      "https://distfiles.macports.org/file/${name}.tar.gz"
    ];
    sha256 = "1vp4zihaxkhi85chkjgd4r4zdg4k2wa3c6pmajhbmx6gr7d8ii89";
  };

  buildInputs = [ zlib ] ++ lib.optionals (buildPlatform != hostPlatform) [ buildPackages.file ];

  doCheck = buildPlatform == hostPlatform;

  meta = with stdenv.lib; {
    homepage = "http://darwinsys.com/file";
    description = "A program that shows the type of files";
    license = licenses.bsd2;
    platforms = platforms.all;
  };
}
