{
    lib,
    stdenv,
    fetchFromGitHub,
    buildPackages,
    ninja,
    pkg-config,
    glib,
    libelf,
    libkqueue,
    sparse,
    meson,
    python3,
}:

stdenv.mkDerivation {
    name = "qemu-bsd-user-l4b";
    version = "devel-20260114";
    src = fetchFromGitHub {
      owner = "sobomax";
      repo = "qemu-bsd-user-l4b";
      rev = "2b76836ebdf23122f3ac9a7638b4e0b70cab6d89";
      postCheckout = ''
        (
          cd $out
          ${lib.getExe buildPackages.meson} subprojects download
        )
      '';
      hash = "sha256-PiDoNbrBVmHMBpsoN2ZiWKMdTo0czoadJ0VNsZLI+zo=";
    };

    nativeBuildInputs = [
        ninja
        pkg-config
        meson
        (python3.withPackages (p: [ p.distlib ]))
        sparse
    ];

    buildInputs = [
        glib
        libelf
        libkqueue
    ];

    NIX_CFLAGS_COMPILE = [
        "-Wno-error=comment"
        "-Wno-error=unused-variable"
        "-D_POSIX_C_SOURCE=200809L"
        #"-g" "-O1" "-U__OPTIMIZE__" "-DDEBUG"
    ];

    #hardeningDisable = [ "fortify" ]; # for debugging
    #dontStrip = true;

    patches = [
      ./sysctl.patch
    ];

    # resilience...
    postPatch = ''
      sed -E -i -e 's/abort\(\)/return -1/g' bsd-user/linux/*.c bsd-user/linux/*.h
    '';

    preConfigure = ''
        patchShebangs scripts
        ./configure --skip-meson --disable-system --target-list=x86_64-bsd-user
    '';

    mesonFlags = [
        "-Dauto_features=disabled"
    ];
}
