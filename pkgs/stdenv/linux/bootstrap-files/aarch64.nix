{
  busybox = import <nix/fetchurl.nix> {
    url = http://tarballs.nixos.org/stdenv-linux/aarch64/bb3ef8a95c9659596b8a34d27881cd30ffea2f9f/busybox;
    sha256 = "12qcml1l67skpjhfjwy7gr10nc86gqcwjmz9ggp7knss8gq8pv7f";
    executable = true;
  };
  bootstrapTools = ./bootstrap-tools-new.tar.xz;
}
