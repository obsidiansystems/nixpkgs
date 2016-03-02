{ stdenv, git, clang,
  fetchFromGitHub, requireFile, fuse,
  openssl, xz, gnutar, gcc,
  automake, autoconf, libtool, clangStdenv, darling-dmg } :

clangStdenv.mkDerivation rec {
  name = "ios-cross-compile-${version}";
  version = "9.2";
  sdkName = "iPhoneOS${version}.sdk";
  sdk = "/nix/store/p6597n3j8g38r1jvwn22f0kaz5lj0h53-iPhoneOS9.2.sdk";
  arch = "armv7";
  cctools_port = fetchFromGitHub {
    owner = "tpoechtrager";
    repo = "cctools-port";
    rev = "7d405492b09fa27546caaa989b8493829365deab";
    sha256 = "0nj1q5bqdx5jm68dispybxc7wnkb6p8p2igpnap9q6qyv2r9p07w";
  };
  ldid = fetchFromGitHub {
    owner = "tpoechtrager";
    repo = "ldid";
    rev = "3064ed628108da4b9a52cfbe5d4c1a5817811400";
    sha256 = "1a6zaz8fgbi239l5zqx9xi3hsrv3jmfh8dkiy5gmnjs6v4gcf6sf";
  };
  buildInputs = [ fuse darling-dmg git xz gnutar openssl automake autoconf libtool clang ];
  alt_wrapper = ./alt_wrapper.c;
  builder = ./9.2_builder.sh;
  meta = {
    description =
    "Provides an iOS cross compiler from 7.1 up to iOS-${version} and ldid";
    platforms = stdenv.lib.platforms.linux;
    maintainers = with stdenv.lib.maintainers; [ fxfactorial ];
    license = stdenv.lib.licenses.gpl2;
  };
}
