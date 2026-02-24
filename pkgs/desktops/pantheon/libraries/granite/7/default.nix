{
  lib,
  stdenv,
  fetchFromGitHub,
  buildPackages,
  nix-update-script,
  meson,
  ninja,
  sassc,
  vala,
  pkg-config,
  libgee,
  libshumate,
  gtk4,
  gtk-doc,
  glib,
  gettext,
  gsettings-desktop-schemas,
  gobject-introspection,
  wrapGAppsHook4,
  withIntrospection ?
    lib.meta.availableOn stdenv.hostPlatform gobject-introspection
    && stdenv.hostPlatform.emulatorAvailable buildPackages,
}:

stdenv.mkDerivation rec {
  pname = "granite";
  version = "7.8.0";

  outputs = [
    "out"
    "dev"
  ];

  src = fetchFromGitHub {
    owner = "elementary";
    repo = "granite";
    tag = version;
    hash = "sha256-UEbe/vAXbd1W7EA1s5qvn8dM9/3CTIyLGMPXzEFu7qM=";
  };

  nativeBuildInputs = [
    gettext
    meson
    ninja
    pkg-config
    sassc
    wrapGAppsHook4
    vala
  ] ++ lib.optionals withIntrospection [
    gobject-introspection
    gtk-doc
  ];

  buildInputs = [
    libshumate # demo
  ];

  propagatedBuildInputs = [
    glib
    gsettings-desktop-schemas # is_clock_format_12h uses "org.gnome.desktop.interface clock-format"
    gtk4
    libgee
  ];

  mesonFlags = [
    (lib.mesonBool "introspection" withIntrospection)
    (lib.mesonBool "documentation" withIntrospection)
    (lib.mesonBool "demo" withIntrospection)
  ];

  passthru = {
    updateScript = nix-update-script { };
  };

  meta = {
    description = "Extension to GTK used by elementary OS";
    longDescription = ''
      Granite is a companion library for GTK and GLib. Among other things, it provides complex widgets and convenience functions
      designed for use in apps built for elementary OS.
    '';
    homepage = "https://github.com/elementary/granite";
    license = lib.licenses.lgpl3Plus;
    platforms = lib.platforms.linux ++ lib.platforms.freebsd;
    teams = [ lib.teams.pantheon ];
    mainProgram = "granite-7-demo";
  };
}
