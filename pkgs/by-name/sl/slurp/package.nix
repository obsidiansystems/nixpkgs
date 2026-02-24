{
  lib,
  stdenv,
  fetchFromGitHub,
  cairo,
  evdev-proto,
  libxkbcommon,
  meson,
  ninja,
  pkg-config,
  scdoc,
  wayland,
  wayland-protocols,
  wayland-scanner,
  buildDocs ? true,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "slurp";
  version = "1.5.0";

  src = fetchFromGitHub {
    owner = "emersion";
    repo = "slurp";
    rev = "v${finalAttrs.version}";
    hash = "sha256-2M8f3kN6tihwKlUCp2Qowv5xD6Ufb71AURXqwQShlXI=";
  };

  depsBuildBuild = [ pkg-config ];

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    wayland-scanner
  ]
  ++ lib.optional buildDocs scdoc;

  buildInputs = [
    cairo
    libxkbcommon
    wayland
    wayland-protocols
  ]
  ++ lib.optionals stdenv.hostPlatform.isFreeBSD [
    evdev-proto
  ];

  strictDeps = true;

  mesonFlags = [ (lib.mesonEnable "man-pages" buildDocs) ];

  meta = {
    changelog = "https://github.com/emersion/slurp/releases/tag/v${finalAttrs.version}";
    description = "Select a region in a Wayland compositor";
    platforms = lib.platforms.linux ++ lib.platforms.freebsd;
    homepage = "https://github.com/emersion/slurp";
    license = lib.licenses.mit;
    mainProgram = "slurp";
    maintainers = with lib.maintainers; [ nickcao ];
  };
})
