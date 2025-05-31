{
  stdenv,
  lib,
  fetchFromGitLab,
  fetchpatch,
  meson,
  ninja,
  pkg-config,
  cjson,
  cmocka,
  mbedtls,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "librist";
  version = "0.2.11";

  src = fetchFromGitLab {
    domain = "code.videolan.org";
    owner = "rist";
    repo = "librist";
    rev = "v${finalAttrs.version}";
    hash = "sha256-xWqyQl3peB/ENReMcDHzIdKXXCYOJYbhhG8tcSh36dY=";
  };

  # avoid rebuild on Linux for now
  patches = lib.optionals stdenv.hostPlatform.isDarwin [
    # https://code.videolan.org/rist/librist/-/issues/192
    ./no-brew-darwin.diff
  ] ++ [
    (fetchpatch {
      url = "https://github.com/freebsd/freebsd-ports/raw/c9b5763a8e183e65f126a92d0de94db29c3644d9/multimedia/librist/files/patch-meson.build";
      hash = "sha256-KRVuoQDsyOg+uRDzHzjo4l5u1rb1BoZZHYQ9dP+p7Gw=";
      extraPrefix = "";
    })
  ];

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
  ];

  buildInputs = [
    cjson
    cmocka
    mbedtls
  ];

  meta = {
    description = "Library that can be used to easily add the RIST protocol to your application";
    homepage = "https://code.videolan.org/rist/librist";
    license = with lib.licenses; [
      bsd2
      mit
      isc
    ];
    maintainers = with lib.maintainers; [ raphaelr ];
    platforms = lib.platforms.all;
  };
})
