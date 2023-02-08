{ lib
, fetchFromGitHub
, buildGoModule
, git
, nodejs
, protobuf
, protoc-gen-go
, protoc-gen-go-grpc
, rustPlatform
, pkg-config
, openssl
, extra-cmake-modules
, fontconfig
, go
}:
let
  version = "1.7.0";
  src = fetchFromGitHub {
    owner = "vercel";
    repo = "turbo";
    rev = "v${version}";
    sha256 = "sha256-KARLBdoXaGXCcVtBFHasltrWub5Y0eI53I/Q2MTQ3xU=";
  };

  go-turbo = buildGoModule rec {
    inherit src version;
    pname = "go-turbo";
    modRoot = "cli";

    vendorSha256 = "Kx/CLFv23h2TmGe8Jwu+S3QcONfqeHk2fCW1na75c0s=";

    nativeBuildInputs = [
      git
      nodejs
      protobuf
      protoc-gen-go
      protoc-gen-go-grpc
    ];

    preBuild = ''
      make compile-protos
    '';

    preCheck = ''
      # Some tests try to run mkdir $HOME
      HOME=$TMP

      # Test_getTraversePath requires that source is a git repo
      # pwd: /build/source/cli
      pushd ..
      git config --global init.defaultBranch main
      git init
      popd
    '';

  };
in
rustPlatform.buildRustPackage rec {
  pname = "turbo";
  inherit src version;
  cargoBuildFlags = [
    "--workspace"
  ];
  RELEASE_TURBO_CLI = "true";

  cargoSha256 = "sha256-jdVus8Ca/iO6tdeaXhAM3FxtDBptTRcuBTKL/rD+OFo=";
  RUSTC_BOOTSTRAP = 1;
  nativeBuildInputs = [
    pkg-config
    extra-cmake-modules
  ];
  buildInputs = [
    openssl
    fontconfig
  ];

  postInstall = ''
    ln -s ${go-turbo}/bin/turbo $out/bin/go-turbo
  '';

  # Browser tests time out with chromium and google-chrome
  doCheck = false;

  meta = with lib; {
    description = "High-performance build system for JavaScript and TypeScript codebases";
    homepage = "https://turbo.build/";
    maintainers = with maintainers; [ dlip ];
    license = licenses.mpl20;
  };
}
