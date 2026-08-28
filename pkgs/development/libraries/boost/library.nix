# Builds one Boost library from its own repository.
#
# A boostorg library repository is not a self-contained CMake project: it
# declares its target and then links `Boost::assert`, `Boost::config` and so on
# without ever importing them, and it installs nothing at all. Both jobs belong
# to the superproject, which does `add_subdirectory(libs/<name>)` followed by
# `boost_install(...)` (see `BoostRoot.cmake`). So we stand in for the
# superproject with a wrapper `CMakeLists.txt` that does exactly those two
# things, plus the `find_package` calls that import the dependencies from their
# own packages.
{
  lib,
  stdenv,
  cmake,
  fetchFromGitHub,
  writeText,

  # From the scope: see default.nix.
  boostCmake,
  version,
  rev,
  enableShared,

  name,
  repo,
  hash,
  deps ? [ ],
  # CMake package names to import, which are targets rather than libraries:
  # `boost_asio_core` is a target of the Boost.Asio package.
  findPackages ? [ ],
  # Whether the library installs itself once it believes it is in a
  # superproject, in which case the wrapper must not install it again.
  selfInstalls ? false,
  # A library that compiles nothing has no `out` to speak of, so it gets a
  # single output instead of an empty one beside a `dev` holding everything.
  headerOnly ? false,
  # Which CMake targets to install. Normally just the library itself, but a few
  # split their interface across helper targets that have to be exported too,
  # or CMake refuses to export the library that links them.
  installTargets ? [ "boost_${name}" ],
  # From overrides.nix, for the few libraries that need something outside Boost.
  buildInputs ? [ ],
  # External packages whose `find_dependency` the installed CMake config calls,
  # so a dependant has to be able to find them too.
  propagatedBuildInputs ? [ ],
  cmakeFlags ? [ ],
  # Extra CMake appended to the wrapper, after the library has been added.
  extraCMake ? "",
  # From patches.nix.
  patches ? [ ],
  postPatch ? "",
  meta ? { },
}:

let
  # Stands in for the superproject: import the dependencies, add the library,
  # install it.
  wrapper = writeText "boost-${name}-CMakeLists.txt" (
    ''
      cmake_minimum_required(VERSION 3.16)
      project(boost_${name}_package VERSION ${version} LANGUAGES CXX)

      # The libraries key off this to decide they are part of a superproject.
      set(BOOST_SUPERPROJECT_VERSION ${version})
      set(BOOST_SUPERPROJECT_SOURCE_DIR "''${CMAKE_CURRENT_SOURCE_DIR}")

      list(APPEND CMAKE_MODULE_PATH "${boostCmake}/include")
      include(BoostInstall)

    ''
    + lib.concatMapStringsSep "\n" (
      target: "find_package(boost_${target} ${version} EXACT REQUIRED)"
    ) findPackages
    + ''

      add_subdirectory(src)
    ''
    + lib.optionalString (!selfInstalls) ''

      boost_install(TARGETS ${lib.concatStringsSep " " installTargets} VERSION ${version} HEADER_DIRECTORY src/include)
    ''
    + lib.optionalString (extraCMake != "") ("\n" + extraCMake)
  );
in
stdenv.mkDerivation {
  pname = "boost-${name}";
  inherit version;

  srcs = [
    (fetchFromGitHub {
      name = "boost-${repo}-source";
      owner = "boostorg";
      inherit repo rev hash;
    })
  ];

  # The library source goes in `src/`; the wrapper project is the root.
  sourceRoot = ".";
  unpackPhase = ''
    runHook preUnpack
    cp -r "$srcs" src
    chmod -R u+w src
    runHook postUnpack
  '';

  postUnpack = ''
    cp ${wrapper} CMakeLists.txt
  '';

  # The wrapper is the root of the source tree and the library is under `src/`,
  # so the upstream commits -- which are relative to the repository root -- have
  # to be applied down there.
  inherit patches postPatch;
  patchFlags = [
    "-p1"
    "-d"
    "src"
  ];

  nativeBuildInputs = [ cmake ];

  inherit buildInputs;

  # Dependencies are propagated: a dependant needs their headers on its include
  # path and their CMake packages on CMAKE_PREFIX_PATH, transitively.
  propagatedBuildInputs = deps ++ propagatedBuildInputs;

  cmakeFlags = [
    (lib.cmakeBool "BUILD_SHARED_LIBS" (enableShared && !stdenv.hostPlatform.isStatic))
    (lib.cmakeBool "BUILD_TESTING" false)
  ]
  # Boost.Predef declared `cmake_minimum_required(VERSION 3.0)` until 1.86, and
  # CMake 4 refuses that outright. Every library from 1.86 on asks for 3.5 or
  # later already, so this stays off there rather than silencing whatever
  # policy warnings a newer release ought to be showing us.
  ++ lib.optional (lib.versionOlder version "1.86") (
    lib.cmakeFeature "CMAKE_POLICY_VERSION_MINIMUM" "3.5"
  )
  ++ cmakeFlags;

  # For a library that compiles something, headers, the CMake package and the
  # propagation belong in `dev`, so that a dependant which only links the shared
  # library does not take a runtime reference to this library's header-only
  # dependencies. A library that compiles nothing has no such split to make.
  outputs =
    if headerOnly then
      [ "out" ]
    else
      [
        "out"
        "dev"
      ];

  strictDeps = true;

  passthru = {
    boostName = name;
    boostRepo = repo;
  };

  meta = {
    description = "Boost.${name} C++ library";
    homepage = "https://github.com/boostorg/${repo}";
    license = lib.licenses.boost;
    platforms = lib.platforms.unix ++ lib.platforms.windows;
    # Boost.Context lacks support for the N32 ABI on mips64. The build succeeds
    # and then anything depending on it fails very cryptically, so it was worth
    # marking on the whole of Boost when Boost was one derivation; now it can
    # sit on the library it is actually about.
    badPlatforms = lib.optionals (name == "context") [
      lib.systems.inspect.patterns.isMips64n32
    ];
  }
  // meta;
}
