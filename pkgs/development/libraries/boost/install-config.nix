# boostorg/boost_install: the umbrella `BoostConfig.cmake`, which is what makes
# `find_package(Boost COMPONENTS filesystem regex ...)` work.
#
# Without it CMake falls back to its own FindBoost module -- removed in CMake 4,
# and in any case a module that hunts for `libboost_<component>` files. That
# fails for the components upstream builds header-only (regex, math), even
# though the library is perfectly usable. BoostConfig resolves each component
# through its `boost_<component>` CMake package instead, so header-only
# components are found like any other.
#
# The superproject installs this file; the per-library builds do not, so
# `everything.nix` puts it in place.
{
  fetchFromGitHub,
  rev,
  hash,
}:

fetchFromGitHub {
  name = "boost-install-source";
  owner = "boostorg";
  repo = "boost_install";
  inherit rev hash;
}
