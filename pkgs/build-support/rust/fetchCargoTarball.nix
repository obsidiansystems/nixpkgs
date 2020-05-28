{ stdenv, cacert, cargo, curl, git, python3 }:
let cargo-vendor-normalise = stdenv.mkDerivation {
  name = "cargo-vendor-normalise";
  src = ./cargo-vendor-normalise.py;
  nativeBuildInputs = [ python3.pkgs.wrapPython ];
  dontUnpack = true;
  installPhase = "install -D $src $out/bin/cargo-vendor-normalise";
  pythonPath = [ python3.pkgs.toml ];
  postFixup = "wrapPythonPrograms";
  doInstallCheck = true;
  installCheckPhase = ''
    # check that ./fetchcargo-default-config.toml is a fix point
    reference=${./fetchcargo-default-config.toml}
    < $reference $out/bin/cargo-vendor-normalise > test;
    cmp test $reference
  '';
  preferLocalBuild = true;
};
mirrors = import ../fetchurl/mirrors.nix;
in
{ name ? "cargo-deps"
, src ? null
, srcs ? []
, patches ? []
, sourceRoot
, sha256
, cargoUpdateHook ? ""
, ...
} @ args:
stdenv.mkDerivation ({
  name = "${name}-vendor.tar.gz";
  nativeBuildInputs = [ cacert cargo cargo-vendor-normalise curl git ];

  phases = "unpackPhase patchPhase buildPhase installPhase";

  inherit (mirrors) hashedMirrors;

  buildPhase = ''
    #########################################################################
    # PDT HACK: Copied from fetchurl's builder.sh. Ideally we refactor this to
    # be more re-usable as a generic hashed-mirror substituter across any FOD
    # builder, including Cargo. This could probably be done in a
    # straightforward manner by exposing the portion checking the hashed
    # mirror as a re-usable `checkHashedMirror` setupHook within fetchurl, and
    # then having other builders (Bazel, Cargo) include it at the infra level.
    downloadedFile="$out"

    tryDownload() {
        local url="$1"
        echo
        header "trying $url"
        local curlexit=18;

        success=

        # if we get error code 18, resume partial download
        while [ $curlexit -eq 18 ]; do
          # keep this inside an if statement, since on failure it doesn't abort the script
          if curl -C - --fail "$url" --output "$downloadedFile"; then
              success=1
              break
          else
              curlexit=$?;
          fi
        done
    }

    tryHashedMirrors() {
        for mirror in $hashedMirrors; do
            url="$mirror/$outputHashAlgo/$outputHash"
            echo Looking for $url
            if curl --retry 0 --connect-timeout 15 \
                --fail --silent --show-error --head "$url" \
                --write-out "%{http_code}" --output /dev/null > code 2> log; then
                tryDownload "$url"
                if test -n "$success"; then exit 0; fi
            else
                # Be quiet about 404 errors, which we interpret as the file
                # not being present on this particular mirror.
                if test "$(cat code)" != 404; then
                    echo "error checking the existence of $url:"
                    cat log
                fi
            fi
        done
    }

    tryHashedMirrors

    # END PDT HACK
    ################################################################################

    # Ensure deterministic Cargo vendor builds
    export SOURCE_DATE_EPOCH=1

    if [[ ! -f Cargo.lock ]]; then
        echo
        echo "ERROR: The Cargo.lock file doesn't exist"
        echo
        echo "Cargo.lock is needed to make sure that cargoSha256 doesn't change"
        echo "when the registry is updated."
        echo

        exit 1
    fi

    # Keep the original around for copyLockfile
    cp Cargo.lock Cargo.lock.orig

    export CARGO_HOME=$(mktemp -d cargo-home.XXX)
    CARGO_CONFIG=$(mktemp cargo-config.XXXX)

    ${cargoUpdateHook}

    cargo vendor $name | cargo-vendor-normalise > $CARGO_CONFIG

    # Add the Cargo.lock to allow hash invalidation
    cp Cargo.lock.orig $name/Cargo.lock

    # Packages with git dependencies generate non-default cargo configs, so
    # always install it rather than trying to write a standard default template.
    install -D $CARGO_CONFIG $name/.cargo/config;
  '';

  # Build a reproducible tar, per instructions at https://reproducible-builds.org/docs/archives/
  installPhase = ''
    tar --owner=0 --group=0 --numeric-owner --format=gnu \
        --sort=name --mtime="@$SOURCE_DATE_EPOCH" \
        -czf $out $name
  '';

  outputHashAlgo = "sha256";
  outputHash = sha256;

  impureEnvVars = stdenv.lib.fetchers.proxyImpureEnvVars;
} // (builtins.removeAttrs args [
  "name" "sha256" "cargoUpdateHook"
]))
