{
  stdenv, buildPackages, fetchurl, fetchpatch,
  runCommand,
  autoconf, automake, libtool,
  enablePython ? false, python ? null,
}:

assert enablePython -> python != null;

stdenv.mkDerivation rec {
  name = "audit-3.0.6"; # at the next release, remove the patches below!

  src = fetchurl {
    url = "https://people.redhat.com/sgrubb/audit/${name}.tar.gz";
    sha256 = "0pnc9wzslks9p6kxw0llp1n8h8yg0frcxl3x84fl0hisa5vlvr63";
  };

  outputs = [ "bin" "dev" "out" "man" ];

  depsBuildBuild = [ buildPackages.stdenv.cc ];
  nativeBuildInputs = stdenv.lib.optionals stdenv.hostPlatform.isMusl
    [ autoconf automake libtool ];
  buildInputs = stdenv.lib.optional enablePython python;

  configureFlags = [
    # z/OS plugin is not useful on Linux,
    # and pulls in an extra openldap dependency otherwise
    "--disable-zos-remote"
    (if enablePython then "--with-python" else "--without-python")
    "--with-arm"
    "--with-aarch64"
  ];

  enableParallelBuilding = true;

  prePatch = ''
    sed -i 's,#include <sys/poll.h>,#include <poll.h>\n#include <limits.h>,' audisp/audispd.c
  '';
  meta = {
    description = "Audit Library";
    homepage = https://people.redhat.com/sgrubb/audit/;
    license = stdenv.lib.licenses.gpl2;
    platforms = stdenv.lib.platforms.linux;
    maintainers = with stdenv.lib.maintainers; [ ];
  };
}
