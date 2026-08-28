# Upstream fixes Nixpkgs carries, as an overlay on top of the generated data in
# `versions/`, so that nothing here has to be merged back into a file that
# `update.py` rewrites.
#
# These are per-library now, and mostly simpler than they were: a patch is the
# upstream commit applied to the repository it was made against, so most need
# none of the `relative`/`stripLen`/`extraPrefix` rewriting that made a commit
# against one library apply inside the monolithic release tarball. The two
# exceptions carry a prefix from the tarball layout and say so.
#
# Three of the old patches went away with the `b2` build rather than being
# dropped: `darwin-no-system-python` and `fix-clang-target` patched Boost.Build
# itself (`tools/build/src/tools/{python,clang}.jam`) and `cmake-paths-*`
# patched the CMake config the monolithic install generated
# (`tools/boost_install/boost-install.jam`). The per-library CMake builds use
# none of those files.
#
# `Fix-cygwin-build-*` was a different matter -- it patched library source, and
# is below.
{
  lib,
  stdenv,
  fetchpatch,
}:

version:

let
  before = bound: lib.versionOlder version bound;
  from = bound: lib.versionAtLeast version bound;
  exactly = which: version == which;

  # Nixpkgs used to carry these as one flattened `Fix-cygwin-build-<release>`
  # patch per release, generated from a fork with `git format-patch
  # --submodule=diff` and sed. They have since been merged into the boostorg
  # repositories, so each is just its own upstream commit again -- which is also
  # the shape the per-library build wants.
  cygwinCommits = {
    "1.87.0" = {
      asio = {
        rev = "d24e5abb62";
        hash = "sha256-K5Ypox3FSgRpPh/hepNlAliyRkV0hVo9BuQMt8sUb00=";
      };
      context = {
        rev = "78000a2db7";
        hash = "sha256-3+S4NC9Meq8y8oqUkem5lLOifJdQ9FfpqiBE1vHdb9k=";
      };
      process = {
        rev = "c9f4ee67d0";
        hash = "sha256-vgeA0CPsAZpGYNAhbZstCkpJo/qM9Z1zL2JftIQO38c=";
      };
      stacktrace = {
        rev = "b39042bea9";
        hash = "sha256-hkDv8GEngTtCURwxepRmGjobKDBpu6XW+/5T2SrsWUw=";
      };
      system = {
        rev = "6dd93221e9";
        hash = "sha256-JfuHY61QyY8uUvJY8idEabC4AcRJdiq8UGz8WglbVkQ=";
      };
    };
    "1.89.0" = {
      asio = {
        rev = "6973686977";
        hash = "sha256-tYiex8mh4WM06HDiAjtXulro8AucfPgb00oSEQfurIc=";
      };
      context = {
        rev = "89cdfdc1af";
        hash = "sha256-3+S4NC9Meq8y8oqUkem5lLOifJdQ9FfpqiBE1vHdb9k=";
      };
      process = {
        rev = "fc085cfb19";
        hash = "sha256-O7o49EduMW3fvlBDQCyiPZxC3wrxCHDi5XMjtmEGNlY=";
      };
      stacktrace = {
        rev = "7d8974c03d";
        hash = "sha256-2KdZesE/pq+SokREsMJ4MEa9DkNTdwCi4x9FgMwx6C0=";
      };
      system = {
        rev = "c2c3f62ea8";
        hash = "sha256-JfuHY61QyY8uUvJY8idEabC4AcRJdiq8UGz8WglbVkQ=";
      };
    };
  };

  cygwinPatches = lib.optionalAttrs stdenv.hostPlatform.isCygwin (
    lib.mapAttrs (library: commit: {
      patches = [
        (fetchpatch {
          name = "cygwin-${library}.patch";
          url = "https://github.com/boostorg/${library}/commit/${commit.rev}.patch";
          inherit (commit) hash;
        })
      ];
    }) (cygwinCommits.${version} or { })
  );

  # Boost.Context miscompiles that Nix in particular kept tripping over.
  contextPatches =
    # Prevents an optimisation that breaks coroutine migration between threads.
    lib.optional (from "1.88.0" && before "1.92.0") (fetchpatch {
      name = "context-coroutine-thread-migration.patch";
      url = "https://github.com/boostorg/context/commit/0921b9fd5c776aec7748475c6c10807e0d51bc6d.patch";
      hash = "sha256-inkym4oZchVON3u4HKzbAHZx52B9Tc/9EWzahag7zCY=";
    })
    # Fixes std::uncaught_exceptions for abandoned coroutines under libstdc++.
    # https://github.com/NixOS/nix/issues/16174
    ++ lib.optional (from "1.88.0" && before "1.93.0") (fetchpatch {
      name = "context-uncaught-exceptions.patch";
      url = "https://github.com/boostorg/context/commit/5883212311535a0046031d74d1568ae173c1e35b.patch";
      hash = "sha256-lfQd0V5A8R82A88tD2PEwkrm9IHtiFkWl//nC9+MEE0=";
    })
    # https://github.com/NixOS/nix/issues/13145
    ++ lib.optional (from "1.88.0" && before "1.89.0") (fetchpatch {
      name = "context-nix-13145.patch";
      url = "https://github.com/boostorg/context/commit/c79564d0de69422ed33f2fbc892908ad510e6a19.patch";
      hash = "sha256-Xi0cAqR3CtCyFZKlmtObT9YYuBXR1yxm352UNt0K91w=";
    })
    # ABI detection.
    ++ lib.optional (exactly "1.83.0") (fetchpatch {
      name = "context-abi-detection.patch";
      url = "https://github.com/boostorg/context/commit/6fa6d5c50d120e69b2d8a1c0d2256ee933e94b3b.patch";
      hash = "sha256-PXv05J62gC409OgJvNDMXaM/jfKHgerEV62I6TSSoYA=";
    })
    # ABI detection on loongarch64 and friends.
    ++ lib.optional (exactly "1.87.0") (fetchpatch {
      name = "context-abi-detection-loongarch.patch";
      url = "https://github.com/boostorg/context/commit/63996e427b4470c7b99b0f4cafb94839ea3670b6.patch";
      hash = "sha256-/UIe/AsPyhFCniV2eYPQciQJUDu8hBdmwK9X0aQpMHw=";
    });

  pythonPatches =
    lib.optional (before "1.81") (fetchpatch {
      name = "python311-compatibility.patch";
      url = "https://github.com/boostorg/python/commit/a218babc8daee904a83f550fb66e5cb3f1cb3013.patch";
      hash = "sha256-tiUVb4El1yFi2aQ6UCVKsbopY18wsKiG4psfvlXViBg=";
      # This commit's paths carry the `libs/python/` the monolithic tree had,
      # where the repository starts at `src/`.
      extraPrefix = "src/";
      stripLen = 2;
    })
    ++ lib.optional (from "1.86" && before "1.87") (fetchpatch {
      name = "numpy-2-compatibility.patch";
      url = "https://github.com/boostorg/python/commit/0474de0f6cc9c6e7230aeb7164af2f7e4ccf74bf.patch";
      hash = "sha256-HmqhHQ4AgxbzKKkzA5MxfEW2EZKsjAlM21HJtWRfEdI=";
    });
  # A library can be named by more than one of the groups below -- Boost.Context
  # has both its own fixes and a cygwin one -- so their patch lists concatenate
  # rather than the later group winning.
  merge =
    groups:
    lib.zipAttrsWith (
      _: values:
      lib.foldl' (
        merged: value:
        merged
        // value
        // lib.optionalAttrs (merged ? patches || value ? patches) {
          patches = (merged.patches or [ ]) ++ (value.patches or [ ]);
        }
      ) { } values
    ) groups;
in
merge [
  (lib.filterAttrs (_: value: value != { }) {
    context = lib.optionalAttrs (contextPatches != [ ]) { patches = contextPatches; };

    python = lib.optionalAttrs (pythonPatches != [ ]) { patches = pythonPatches; };

    # A typo in a template that clang >= 19 and gcc >= 15 reject.
    thread = lib.optionalAttrs (before "1.88") {
      patches = [
        (fetchpatch {
          name = "thread-template-typo.patch";
          url = "https://github.com/boostorg/thread/commit/49ccf9c30a0ca556873dbf64b12b0d741d1b3e66.patch";
          hash = "sha256-2g4yK+217pfv4vYZE9z3O0AMwYZ+SrvKnAfJG7LY2m4=";
        })
      ];
    };

    # An ill-formed constant expression, an error by default in clang 16.
    log = lib.optionalAttrs (before "1.80") {
      patches = [
        (fetchpatch {
          name = "log-ill-formed-constant-expression.patch";
          url = "https://github.com/boostorg/log/commit/77f1e20bd69c2e7a9e25e6a9818ae6105f7d070c.patch";
          hash = "sha256-+tlbn/OR3janb/5rzDcyIDTyjoMAw2H4UNh0Z1z2ddU=";
        })
      ];
    };

    # `::utimbuf` and `::utime` undeclared: a missing <utime.h> on the code path
    # taken when the *at APIs are unavailable, which is the path the CMake build
    # takes. Fixed upstream in 1.81.
    # https://github.com/boostorg/filesystem/issues/250
    filesystem = lib.optionalAttrs (exactly "1.80.0") {
      patches = [
        (fetchpatch {
          name = "filesystem-missing-utime-include.patch";
          url = "https://github.com/boostorg/filesystem/commit/5864f397ccad30f6e73221b90bdac57a303b9752.patch";
          hash = "sha256-ksABNDrzQLqKjW4p3ihWoIR1gnJEn0EFGMgPcv0SfLI=";
          # The commit also touches the release notes, which are not shipped.
          includes = [ "src/operations.cpp" ];
        })
      ];
    };

    # libc++ 15 dropped std::unary_function and std::binary_function in C++17.
    config = lib.optionalAttrs (before "1.81") {
      patches = [
        (fetchpatch {
          name = "config-libcpp15.patch";
          url = "https://www.boost.org/patches/1_80_0/0005-config-libcpp15.patch";
          hash = "sha256-w+M5Cmysyc7XNFHsiyihPX2LadQq2r13MpjYuIvF6jg=";
          # Unlike the GitHub commits, this one is against the unpacked release
          # tarball, so its paths start with a `boost_1_80_0/` component where the
          # repository has `include/`.
          stripLen = 1;
          extraPrefix = "include/";
        })
      ];
    };

    # Another ill-formed constant expression flagged by clang 16.
    numeric_conversion = lib.optionalAttrs (before "1.81") {
      patches = [
        (fetchpatch {
          name = "numeric-conversion-ill-formed-constant-expression.patch";
          url = "https://github.com/boostorg/numeric_conversion/commit/50a1eae942effb0a9b90724323ef8f2a67e7984a.patch";
          hash = "sha256-OPm0/xcSbUE5lHY60UpJJJWRH9E9d2X22fL3DRF9pXA=";
        })
      ];
    };

    # operator<< for shared_ptr and intrusive_ptr.
    # https://github.com/boostorg/smart_ptr/issues/115
    smart_ptr = lib.optionalAttrs (exactly "1.87.0") {
      patches = [
        (fetchpatch {
          name = "smart-ptr-operator-shift.patch";
          url = "https://github.com/boostorg/smart_ptr/commit/e7433ba54596da97cb7859455cd37ca140305a9c.patch";
          hash = "sha256-s8bxSo57uV3PfMXMGdouUaP4wPSGrkKeVY2FzjcRMMI=";
        })
      ];
    };
  })

  (lib.optionalAttrs (exactly "1.87.0") (
    # `,@progbits` breaks compilation for 32-bit ARM with clang. The GDB pretty
    # printers that carry it are spread over four libraries.
    # https://github.com/ned14/outcome/pull/308
    # https://github.com/boostorg/json/pull/1064
    lib.genAttrs
      [
        "outcome"
        "json"
        "unordered"
        "interprocess"
      ]
      (_: {
        postPatch = ''
          find src/include -name '*.h' -o -name '*.hpp' -o -name '*.py' \
            | xargs --no-run-if-empty sed -i 's/,@progbits,1/,%progbits,1/g'
        '';
      })
  ))

  cygwinPatches
]
