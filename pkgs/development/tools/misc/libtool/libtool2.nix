{ lib, stdenv, fetchurl, m4
, runtimeShell
, updateAutotoolsGnuConfigScriptsHook
, file
}:

# Note: this package is used for bootstrapping fetchurl, and thus
# cannot use fetchpatch! All mutable patches (generated by GitHub or
# cgit) that are needed here should be included directly in Nixpkgs as
# files.

stdenv.mkDerivation rec {
  pname = "libtool";
  version = "2.4.7";

  src = fetchurl {
    url = "mirror://gnu/libtool/${pname}-${version}.tar.gz";
    sha256 = "sha256-BOlsJATqcMWQxUbrpCAqThJyLGQAFsErmy8c49SB6ag=";
  };

  outputs = [ "out" "lib" ];

  # FILECMD was added in libtool 2.4.7; previous versions hardwired `/usr/bin/file`
  #   https://lists.gnu.org/archive/html/autotools-announce/2022-03/msg00000.html
  FILECMD = "${file}/bin/file";

  # https://lists.gnu.org/archive/html/libtool-patches/2022-08/msg00000
  # `llvm-ranlab` does not have a `-t` flag.
  patches = lib.optional stdenv.targetPlatform.isOpenBSD ./fix-openbsd.patch;

  postPatch =
  # libtool commit da2e352735722917bf0786284411262195a6a3f6 changed
  # the shebang from `/bin/sh` (which is a special sandbox exception)
  # to `/usr/bin/env sh`, meaning that we now need to patch shebangs
  # in libtoolize.in:
  ''
    substituteInPlace libtoolize.in       --replace '#! /usr/bin/env sh' '#!${runtimeShell}'
    # avoid help2man run after 'libtoolize.in' update
    touch doc/libtoolize.1
  '';

  strictDeps = true;
  # As libtool is an early bootstrap dependency try hard not to
  # add autoconf and automake or help2man dependencies here. That way we can
  # avoid pulling in perl and get away with just an `m4` depend.
  nativeBuildInputs = [ updateAutotoolsGnuConfigScriptsHook m4 file ];
  propagatedBuildInputs = [ m4 file ];

  # Don't fixup "#! /bin/sh" in Libtool, otherwise it will use the
  # "fixed" path in generated files!
  dontPatchShebangs = true;
  dontFixLibtool = true;

  # XXX: The GNU ld wrapper does all sorts of nasty things wrt. RPATH, which
  # leads to the failure of a number of tests.
  doCheck = false;
  doInstallCheck = false;

  enableParallelBuilding = true;

  meta = with lib; {
    description = "GNU Libtool, a generic library support script";
    longDescription = ''
      GNU libtool is a generic library support script.  Libtool hides
      the complexity of using shared libraries behind a consistent,
      portable interface.

      To use libtool, add the new generic library building commands to
      your Makefile, Makefile.in, or Makefile.am.  See the
      documentation for details.
    '';
    homepage = "https://www.gnu.org/software/libtool/";
    license = licenses.gpl2Plus;
    maintainers = [ ];
    platforms = platforms.unix;
    mainProgram = "libtool";
  };
}
