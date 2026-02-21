{
  stdenv,
  lib,
  fetchurl,
  buildPackages,
  meson,
  ninja,
  pkg-config,
  gobject-introspection,
  vala,
  gi-docgen,
  glib,
  gssdp_1_6,
  libsoup_3,
  libxml2,
  gnome,
  withIntrospection ?
    lib.meta.availableOn stdenv.hostPlatform gobject-introspection
    && stdenv.hostPlatform.emulatorAvailable buildPackages,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "gupnp";
  version = "1.6.9";

  outputs = [
    "out"
    "dev"
  ] ++ lib.optionals withIntrospection [
    "devdoc"
  ];

  src = fetchurl {
    url = "mirror://gnome/sources/gupnp/${lib.versions.majorMinor finalAttrs.version}/gupnp-${finalAttrs.version}.tar.xz";
    hash = "sha256-Lttu42E1WOYvU4c1NoruJxUbfgnU4uLFFgaDPagBhps=";
  };

  depsBuildBuild = [
    pkg-config
  ];

  nativeBuildInputs = [
    glib
    meson
    ninja
    pkg-config
  ] ++ lib.optionals withIntrospection [
    gobject-introspection
    vala
    gi-docgen
  ];

  propagatedBuildInputs = [
    glib
    gssdp_1_6
    libsoup_3
    libxml2
  ];

  mesonFlags = [
    (lib.mesonBool "introspection" withIntrospection)
    (lib.mesonBool "vapi" withIntrospection)
    (lib.mesonBool "gtk_doc" withIntrospection)
  ];

  # On Darwin: Failed to bind socket, Operation not permitted
  doCheck = !stdenv.hostPlatform.isDarwin;

  postFixup = lib.optionalString withIntrospection ''
    # Cannot be in postInstall, otherwise _multioutDocs hook in preFixup will move right back.
    moveToOutput "share/doc" "$devdoc"
  '';

  passthru = {
    updateScript = gnome.updateScript {
      attrPath = "gupnp_1_6";
      packageName = "gupnp";
    };
  };

  meta = {
    homepage = "http://www.gupnp.org/";
    description = "Implementation of the UPnP specification";
    mainProgram = "gupnp-binding-tool-1.6";
    license = lib.licenses.lgpl2Plus;
    platforms = lib.platforms.unix;
  };
})
