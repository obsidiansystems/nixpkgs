{ stdenv, buildPackages
, gcc, glibc
, autoreconfHook264, fetchpatch
}:

stdenv.mkDerivation rec {
  name = "libatomic-${version}";
  inherit (gcc.cc) src version;

  # Single output because no headers

  strictDeps = true;
  nativeBuildInputs = [ autoreconfHook264 ];

  postUnpack = ''
    mkdir -p ./build
    buildRoot=$(readlink -e "./build")
  '';

  postPatch = ''
    sourceRoot=$(readlink -e "./libatomic")
  '';

  patches = [
    # Fix --disable-dependency-tracking
    (fetchpatch {
      url = "https://gcc.gnu.org/bugzilla/attachment.cgi?id=30880";
      sha256 = "0zy7df68szby82gfj1kyinr68h6n4fisi7djfihg4azqmsaa80dr";
    })
    # Fix --disable-multilib
    (fetchpatch {
      url = "https://gcc.gnu.org/bugzilla/attachment.cgi?id=44469";
      sha256 = "109m900w9gffacznvn4dhrkid81xs9s3b8bhxiphsqyyb980rrnf";
    })
  ];

  # TODO(@Ericson2314): should autoreconfHook use sourceRoot?
  preAutoreconf = ''
    cd "$sourceRoot"
    autoconf
  '';

  preConfigure = ''
    cd "$buildRoot"
    configureScript=$sourceRoot/configure
  '';

  configurePlatforms = [ "build" "host" ];
  configureFlags = [
    "--disable-dependency-tracking"
    "--disable-multilib" "--with-multilib-list="
  ];
}
