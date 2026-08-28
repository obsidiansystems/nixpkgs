# boostorg/cmake: BoostInstall and the other modules every library's
# CMakeLists.txt includes, which the superproject normally puts on the module
# path. `library.nix`'s wrapper does it instead.
{
  fetchFromGitHub,
  rev,
  hash,
}:

fetchFromGitHub {
  name = "boost-cmake-source";
  owner = "boostorg";
  repo = "cmake";
  inherit rev hash;
}
