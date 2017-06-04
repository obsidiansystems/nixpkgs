{ stdenv, buildPackages
, fetchurl, pkgconfig, ncurses, gzip
, sslSupport ? true, openssl ? null
, buildPlatform, hostPlatform
}:

assert sslSupport -> openssl != null;

stdenv.mkDerivation rec {
  name = "lynx-${version}";
  version = "2.8.9dev.11";

  src = fetchurl {
    url = "http://invisible-mirror.net/archives/lynx/tarballs/lynx${version}.tar.bz2";
    sha256 = "1cqm1i7d209brkrpzaqqf2x951ra3l67dw8x9yg10vz7rpr9441a";
  };

  configureFlags = []
    ++ stdenv.lib.optional sslSupport "--with-ssl=${openssl.dev}"
    # TODO(@Ericson2314) this option doesn't really have much to do with
    # cross-compilation, and should probably be controlled separately
    ++ stdenv.lib.optional (hostPlatform != buildPlatform) "--enable-widec";

  nativeBuildInputs = stdenv.lib.optional sslSupport pkgconfig;

  buildInputs = [ ncurses gzip ]
    ++ stdenv.lib.optional (hostPlatform != buildPlatform) buildPackages.stdenv.cc;

  meta = with stdenv.lib; {
    homepage = http://lynx.isc.org/;
    description = "A text-mode web browser";
    platforms = platforms.unix;
  };
}
