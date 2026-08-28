# Fetches every boostorg repository with a deliberately wrong hash, so that
# update.py can read the real ones out of the failures. Not used by the build.
#
# This is not the usual way round -- a multi-source updater would normally call
# nix-prefetch-github -- but that is one GitHub API call per repository, and
# Boost is ~157 repositories per release: one run exceeds the 60/hour
# unauthenticated rate limit twice over. See `hashes` in update.py.
{
  tag,
  # JSON array of repository names, passed with --argstr from update.py.
  repos,
}:

let
  pkgs = import <nixpkgs> { };
in
builtins.listToAttrs (
  map (repo: {
    name = repo;
    value = pkgs.fetchFromGitHub {
      name = "boost-${repo}-source";
      owner = "boostorg";
      inherit repo;
      rev = tag;
      hash = pkgs.lib.fakeHash;
    };
  }) (builtins.fromJSON repos)
)
