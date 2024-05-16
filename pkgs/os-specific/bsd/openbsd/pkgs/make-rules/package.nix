{
  fetchpatch,
  lib,
  mkDerivation,
  stdenv,
}:

mkDerivation {
  path = "share/mk";
  noCC = true;

  buildInputs = [ ];
  nativeBuildInputs = [ ];

  dontBuild = true;

  patches = [
    (fetchpatch {
      name = "ar.patch";
      url = "https://marc.info/?l=openbsd-tech&m=171575284906018&q=raw";
      sha256 = "1im4p0v8dgq7m8g53x1w8gjs0zy8vqrw82rq17iw3nj4g7vxvvnh";
    })
  ];

  postPatch = ''
    # Need to replace spaces with tabs due to a difference between
    # openbsd and netbsd make
    substituteInPlace share/mk/bsd.dep.mk \
      --replace "       sinclude" "			sinclude"

    sed -i -E \
      -e 's|/usr/lib|\$\{LIBDIR\}|' \
      share/mk/bsd.prog.mk
  '';

  installPhase = ''
    cp -r share/mk $out
  '';

  meta.platforms = lib.platforms.unix;
}
