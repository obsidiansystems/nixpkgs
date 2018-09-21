{ lib, stdenv
, fetchurl
, pkg-config
, autoreconfHook
, db48
, sqlite
, boost
, zeromq
, hexdump
, zlib
, miniupnpc
, qtbase ? null
, qttools ? null
, wrapQtAppsHook ? null
, util-linux
, python3
, qrencode
, libevent
, nixosTests
, withGui ? stdenv.hostPlatform.isLinux
, withWallet ? !stdenv.hostPlatform.isWindows
}:

with lib;
let
  version = "0.21.1";
  majorMinorVersion = versions.majorMinor version;
  desktop = fetchurl {
    url = "https://raw.githubusercontent.com/bitcoin-core/packaging/${majorMinorVersion}/debian/bitcoin-qt.desktop";
    sha256 = "0cpna0nxcd1dw3nnzli36nf9zj28d2g9jf5y0zl9j18lvanvniha";
  };
in
stdenv.mkDerivation rec {
  pname = if withGui then "bitcoin" else "bitcoind";
  inherit version;

  src = fetchurl {
    urls = [
      "https://bitcoincore.org/bin/bitcoin-core-${version}/bitcoin-${version}.tar.gz"
      "https://bitcoin.org/bin/bitcoin-core-${version}/bitcoin-${version}.tar.gz"
    ];
    sha256 = "caff23449220cf45753f312cefede53a9eac64000bb300797916526236b6a1e0";
  };

  patches = [
    ./mingw-use-pkg-config.patch
  ];

  nativeBuildInputs =
    [ pkg-config autoreconfHook ]
    ++ optional stdenv.isDarwin hexdump
    ++ optional withGui wrapQtAppsHook;
  buildInputs = [
    boost
  ] ++ optionals (!stdenv.hostPlatform.isWindows) [
    zlib zeromq miniupnpc libevent 
  ] ++ optionals stdenv.isLinux [ util-linux ]
    ++ optionals withWallet [ db48 sqlite ]
    ++ optionals withGui [ qtbase qttools qrencode ];

  postInstall = optional withGui ''
    install -Dm644 ${desktop} $out/share/applications/bitcoin-qt.desktop
    substituteInPlace $out/share/applications/bitcoin-qt.desktop --replace "Icon=bitcoin128" "Icon=bitcoin"
    install -Dm644 share/pixmaps/bitcoin256.png $out/share/pixmaps/bitcoin.png
  '';

  configureFlags = [
    "--with-boost-libdir=${boost.out}/lib"
    "--disable-bench"
  ] ++ optionals (!doCheck) [
    "--disable-tests"
    "--disable-gui-tests"
  ] ++ optionals (!withWallet) [
    "--disable-wallet"
  ] ++ optionals withGui [
    "--with-gui=qt5"
    "--with-qt-bindir=${qtbase.dev}/bin:${qttools.dev}/bin"
  ];

  checkInputs = [ python3 ];

  doCheck = true;

  checkFlags =
    [ "LC_ALL=C.UTF-8" ]
    # QT_PLUGIN_PATH needs to be set when executing QT, which is needed when testing Bitcoin's GUI.
    # See also https://github.com/NixOS/nixpkgs/issues/24256
    ++ optional withGui "QT_PLUGIN_PATH=${qtbase}/${qtbase.qtPluginPrefix}";

  enableParallelBuilding = true;

  passthru.tests = {
    smoke-test = nixosTests.bitcoind;
  };

  meta = {
    description = "Peer-to-peer electronic cash system";
    longDescription = ''
      Bitcoin is a free open source peer-to-peer electronic cash system that is
      completely decentralized, without the need for a central server or trusted
      parties. Users hold the crypto keys to their own money and transact directly
      with each other, with the help of a P2P network to check for double-spending.
    '';
    homepage = "https://bitcoin.org/";
    downloadPage = "https://bitcoincore.org/bin/bitcoin-core-${version}/";
    changelog = "https://bitcoincore.org/en/releases/${version}/";
    maintainers = with maintainers; [ prusnak roconnor ];
    license = licenses.mit;
    # bitcoin needs hexdump to build, which doesn't seem to build on darwin at the moment.
    broken = stdenv.hostPlatform.isDarwin
      || !(withGui -> withWallet)
      || (withGui && !stdenv.hostPlatform.isLinux);
    platforms = platforms.all;
  };
}
