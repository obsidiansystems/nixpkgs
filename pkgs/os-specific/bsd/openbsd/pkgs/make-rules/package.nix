{
  fetchpatch,
  lib,
  mkDerivation,
}:

mkDerivation {
  path = "share/mk";
  noCC = true;

  buildInputs = [ ];
  nativeBuildInputs = [ ];

  dontBuild = true;

  patches = [
    (fetchpatch {
      url = "https://marc.info/?l=openbsd-tech&m=171575284906018&q=raw";
      sha256 = "sha256-bigxJGbaf9mCmFXxLVzQpnUUaEMMDfF3eZkTXVzd6B8=";
    })
    ./netbsd-make-sinclude.patch
    (fetchpatch {
      url = "https://marc.info/?l=openbsd-tech&m=171972639411562&q=raw";
      sha256 = "sha256-p4izV6ZXkfgJud+ZZU1Wqr5qFuHUzE6qVXM7QnXvV3k=";
      includes = [ "share/mk/*" ];
    })
  ];

  postPatch = ''
    sed -i -E \
      -e 's|/usr/lib|\$\{LIBDIR\}|' \
      share/mk/bsd.prog.mk
  '';

  installPhase = ''
    cp -r share/mk $out
  '';

  meta.platforms = lib.platforms.unix;
}
