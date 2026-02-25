{
  lib,
  stdenv,
  fetchFromSourcehut,
  buildPackages,
  pkg-config,
  scdoc,
  wayland-scanner,
  wayland,
  wayland-protocols,
  evdev-proto,
  libxkbcommon,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "wev";
  version = "1.1.0";

  src = fetchFromSourcehut {
    owner = "~sircmpwn";
    repo = "wev";
    rev = finalAttrs.version;
    hash = "sha256-0ZA44dMDuVYfplfutOfI2EdPNakE9KnOuRfk+CEDCRk=";
  };

  strictDeps = true;
  # for scdoc
  nativeBuildInputs = [
    pkg-config
    scdoc
    wayland-scanner
    wayland-protocols
    wayland
    libxkbcommon
  ];
  buildInputs = [
    wayland
    wayland-protocols
    libxkbcommon
  ] ++ lib.optionals stdenv.hostPlatform.isFreeBSD [
    evdev-proto
  ];

  # This package's build system is not set up correctly for cross compilation.
  # It uses the base pkg-config for everything instead of using the prefixed versions.
  # If we put these deps into the "right" places it either doesn't pick it up or picks it up
  # and then the final product segfaults.
  preConfigure = ''
    mkdir -p $TMP/bin
    ln -s $(type -p $PKG_CONFIG) $TMP/bin/pkg-config
    export PATH=$PATH:$TMP/bin
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:${lib.getDev buildPackages.wayland-scanner}/lib/pkgconfig"
  '';

  installFlags = [ "PREFIX=$(out)" ];

  meta = {
    homepage = "https://git.sr.ht/~sircmpwn/wev";
    description = "Wayland event viewer";
    longDescription = ''
      This is a tool for debugging events on a Wayland window, analogous to the
      X11 tool xev.
    '';
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ wineee ];
    platforms = lib.platforms.linux ++ lib.platforms.freebsd;
    mainProgram = "wev";
  };
})
