# One Boost release, as a scope of individual libraries.
#
# `versions/<version>.json` is generated -- see `update.py`. It records, for
# every boostorg library submodule, the repository it lives in, the hash of its
# source at the release tag, the CMake packages it installs, and the packages
# its target links against.
{
  lib,
  newScope,
  # Passed in rather than resolved from the scope: Boost has a library called
  # `mpi` too, and the scope would shadow it into an infinite recursion.
  mpi,
}:

# The data file generated for the release, from `versions/`.
versionFile:

let
  data = lib.importJSON versionFile;

  inherit (data) version;
  rev = "boost-${version}";

  # Which library installs which CMake package. A library may install several
  # (Boost.Asio installs boost_asio, boost_asio_core, ...), and a dependency
  # may name any of them, so a target does not always share its library's name.
  provider = lib.listToAttrs (
    lib.concatLists (
      lib.mapAttrsToList (
        name: library: map (target: lib.nameValuePair target name) library.provides
      ) data.libraries
    )
  );

  # Libraries that need an interpreter or an MPI implementation. They are always
  # in the scope, but stay out of `everything` unless asked for, so that plain
  # `boost` does not drag Python and MPI into every closure.
  optional = {
    enablePython = [
      "python"
      "parameter_python"
    ];
    useMpi = [
      "mpi"
      "graph_parallel"
      "property_map_parallel"
    ];
  };

  # The options the single-derivation Boost took. They no longer change how a
  # library is built so much as which libraries `everything` gathers up.
  defaults = {
    enableShared = true;
    enableStatic = false;
    enablePython = false;
    enableNumpy = false;
    useMpi = false;
    # Which interpreter Boost.Python is built against, when it is wanted at all.
    python = null;
    numpy = null;
  };

  scopeFor =
    config:
    let
      settings = defaults // config;
    in
    lib.makeScope newScope (
      self:
      let
        overrides = self.callPackage ./overrides.nix { inherit mpi; } version;

        # Upstream fixes, kept out of the generated data so `update.py` never
        # has to merge them back in.
        patches = self.callPackage ./patches.nix { } version;

        # `boost.override { enablePython = true; inherit python; }` asks for a
        # particular interpreter rather than the default one in overrides.nix.
        # Boost.Python builds its NumPy half only when NumPy is there to be
        # found, so `enableNumpy` has to put it in the build inputs. Dependants
        # ask for it without naming one -- rdkit does -- so fall back to the
        # interpreter's own.
        numpyFor = python: if settings.numpy != null then settings.numpy else python.pkgs.numpy;

        chosenPython = lib.optionalAttrs (settings.python != null) (
          lib.genAttrs optional.enablePython (_: {
            buildInputs = [
              settings.python
            ]
            ++ lib.optional settings.enableNumpy (numpyFor settings.python);
            cmakeFlags = [ (lib.cmakeFeature "Python_EXECUTABLE" (lib.getExe settings.python)) ];
          })
        );

        # Boost.Python only learned about NumPy 2 in 1.86.
        numpyBroken = lib.optionalAttrs settings.enableNumpy {
          python.meta.broken =
            lib.versionOlder version "1.86"
            && (settings.numpy == null || lib.versionAtLeast settings.numpy.version "2");
        };

        libraries = lib.mapAttrs (
          name: library:
          let
            override = overrides.${name} or { };
            # A library whose `extraCMake` compiles something upstream leaves
            # uncompiled needs targets its own CMakeLists never mentions, and
            # which therefore never reach the generated deps.
            targets = library.deps ++ (override.extraTargets or [ ]);
          in
          self.callPackage ./library.nix (
            {
              inherit name;
              inherit (library)
                repo
                hash
                selfInstalls
                headerOnly
                ;
              # `find_package` names the target; the dependency is on whichever
              # library installs it.
              findPackages = targets;
              deps = map (owner: self.${owner}) (lib.unique (map (target: provider.${target}) targets));
            }
            // (removeAttrs override [ "extraTargets" ])
            // (patches.${name} or { })
            // (chosenPython.${name} or { })
            // (numpyBroken.${name} or { })
          )
        ) data.libraries;

        # Boost.Python is where NumPy support lives, so asking for one asks for
        # the other.
        excluded =
          lib.optionals (!(settings.enablePython || settings.enableNumpy)) optional.enablePython
          ++ lib.optionals (!settings.useMpi) optional.useMpi;
      in
      libraries
      // {
        inherit version rev;

        boostCmake = self.callPackage ./cmake-modules.nix { hash = data.cmakeHash; };

        boostInstall = self.callPackage ./install-config.nix { hash = data.installHash; };

        # CMake builds one or the other, so unlike the `b2` build there is no
        # way to get both out of a single package. Asking for static gets
        # static.
        enableShared = settings.enableShared && !settings.enableStatic;

        includedLibraries = lib.attrValues (removeAttrs libraries excluded);

        # Read through overrides.nix rather than straight from the data:
        # Boost.Regex is header-only as far as upstream is concerned, but
        # `extraCMake` compiles the POSIX API into it, and taking the generated
        # answer would leave `libboost_regex.so` out of the join.
        runtimeLibraries = lib.attrValues (
          lib.filterAttrs (
            name: _: !((overrides.${name} or { }).headerOnly or data.libraries.${name}.headerOnly or false)
          ) (removeAttrs libraries excluded)
        );

        # The non-Boost packages the included libraries' installed CMake configs
        # call `find_dependency` on. Collected from overrides.nix rather than
        # listed again, so the two cannot drift apart.
        externalDependencies = lib.unique (
          lib.concatMap (name: (overrides.${name} or { }).propagatedBuildInputs or [ ]) (
            lib.attrNames (removeAttrs libraries excluded)
          )
        );

        everything = self.callPackage ./everything.nix { } {
          passthru = {
            inherit libraries;
            # `boost.override { enablePython = true; }` and friends, as the
            # single-derivation Boost accepted them.
            override = args: (scopeFor (settings // args)).everything;
            updateScript = [
              ./update.py
              version
            ];
            tests.split = self.callPackage ./tests.nix { boostPackages = self; };
          };
        };
      }
    );
in
scopeFor { }
