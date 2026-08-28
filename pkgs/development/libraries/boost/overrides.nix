# The handful of Boost libraries that need something from outside Boost.
#
# Everything else in `versions/*.json` is generated; this is the deliberately
# hand-kept exception list, because a library's CMakeLists.txt does not say
# which system package satisfies its `find_package(OpenSSL)`.
{
  lib,
  stdenv,
  bzip2,
  icu,
  mpi,
  openssl,
  python3,
  xz,
  zlib,
  zstd,
}:

version:

{
  # Boost.Context picks its assembly by asking CMake what it is building for,
  # and gets it wrong when cross-compiling: `if(WIN32 OR CYGWIN)` is false in a
  # cross configuration targeting Cygwin, so it takes the ELF default and then
  # fails assembling `make_x86_64_sysv_elf_gas.S` for a PE/COFF target.
  #
  # The `b2` build never relied on that detection -- it passed `binary-format`
  # and `abi` computed from hostPlatform -- so compute them the same way here.
  # Both are cache variables, so setting them simply wins.
  context.cmakeFlags =
    let
      inherit (stdenv) hostPlatform;
    in
    lib.optionals (hostPlatform != stdenv.buildPlatform) [
      (lib.cmakeFeature "BOOST_CONTEXT_BINARY_FORMAT" (
        if hostPlatform.isWindows || hostPlatform.isCygwin then
          "pe"
        else if hostPlatform.isMacho then
          "mach-o"
        else
          "elf"
      ))
      (lib.cmakeFeature "BOOST_CONTEXT_ABI" (
        if hostPlatform.parsed.cpu.family == "arm" then
          "aapcs"
        else if hostPlatform.isWindows || hostPlatform.isCygwin then
          "ms"
        else if hostPlatform.isMips32 then
          "o32"
        else if hostPlatform.isMips64n64 then
          "n64"
        else
          "sysv"
      ))
    ];

  # The compression filters. Every one of these is optional in Boost.Iostreams'
  # CMakeLists and silently switches itself off when its library is not found,
  # so the options are set explicitly: a dependant discovering the filters are
  # missing by failing to link (as lucene++ did) is a much worse way to find
  # out. The `b2` build had all four unconditionally.
  iostreams = {
    propagatedBuildInputs = [
      zlib
      bzip2
      xz
      zstd
    ];
    cmakeFlags = [
      (lib.cmakeBool "BOOST_IOSTREAMS_ENABLE_ZLIB" true)
      (lib.cmakeBool "BOOST_IOSTREAMS_ENABLE_BZIP2" true)
      (lib.cmakeBool "BOOST_IOSTREAMS_ENABLE_LZMA" true)
      (lib.cmakeBool "BOOST_IOSTREAMS_ENABLE_ZSTD" true)
    ];
  };

  # Unicode support in Boost.Regex and the ICU backend of Boost.Locale. The
  # single-derivation Boost had these on by default (`enableIcu`), and CMake
  # silently builds without them if ICU is not there to be found.
  #
  # Boost.Regex keeps its ICU support in a separate `boost_regex_icu` target
  # rather than in the library itself, so that one has to be installed too or
  # nothing can find it. (`libboost_regex.so` having no ICU in its `DT_NEEDED`
  # is upstream's design here, not a missing dependency.)
  regex = {
    propagatedBuildInputs = [ icu ];
    extraTargets = [ "core" ];
    # Header-only as far as upstream is concerned, but `extraCMake` below
    # compiles the POSIX API into it, so it does have an `out` after all.
    headerOnly = false;
    installTargets = [
      "boost_regex"
      "boost_regex_icu"
    ];

    # Upstream's CMakeLists builds Boost.Regex header-only and leaves
    # `src/posix_api.cpp` and `src/wide_posix_api.cpp` -- the deprecated POSIX C
    # API -- uncompiled, where `b2` always produced a `libboost_regex`.
    #
    # A CMake dependant does not care, but an autoconf one does: AX_BOOST_REGEX
    # link-tests `-lboost_regex`, so with no such file the check fails however
    # usable the headers are. That is what breaks source-highlight, and with it
    # gdb and valgrind. So the library is built here to keep the file where
    # everything expects it.
    extraCMake = ''
      add_library(boost_regex_posix src/src/posix_api.cpp src/src/wide_posix_api.cpp)
      set_target_properties(boost_regex_posix PROPERTIES
        OUTPUT_NAME boost_regex
        VERSION ${version}
        SOVERSION ${version}
      )
      target_link_libraries(boost_regex_posix PUBLIC Boost::regex Boost::core)
      install(TARGETS boost_regex_posix
        LIBRARY DESTINATION "''${CMAKE_INSTALL_LIBDIR}"
        ARCHIVE DESTINATION "''${CMAKE_INSTALL_LIBDIR}"
      )
    '';
  };

  locale.propagatedBuildInputs = [ icu ];

  # Boost.Stacktrace installs its four variants but never the `boost_stacktrace`
  # umbrella that selects between them, so `find_package(Boost COMPONENTS
  # stacktrace)` finds nothing. It also breaks the static build outright:
  # `boost_stacktrace_from_exception` links the umbrella, and CMake refuses to
  # export a target that links one which is not itself exported.
  stacktrace.extraCMake = ''
    boost_install(TARGETS boost_stacktrace VERSION ${version} HEADER_DIRECTORY src/include)
  '';

  # Boost.DLL's interface is split across helper targets, and CMake will not
  # export a target that links targets which are not themselves exported.
  dll = lib.optionalAttrs (lib.versionAtLeast version "1.89") {
    installTargets = [
      "boost_dll"
      "boost_dll_base"
      "boost_dll_boost_fs"
      "boost_dll_std_fs"
    ];
  };

  # The TLS users. Boost.MySQL shows why these matter: without OpenSSL it
  # disables itself, and where it does that decides what the build does rather
  # than whether it works. Up to 1.82 it returns before declaring its target, so
  # `boost_install` fails outright; from 1.86 it declares the target first and
  # then returns, so the build succeeds and quietly installs a stub with no TLS.
  cobalt.propagatedBuildInputs = [ openssl ];
  mqtt5.propagatedBuildInputs = [ openssl ];
  mysql.propagatedBuildInputs = [ openssl ];
  redis.propagatedBuildInputs = [ openssl ];

  mpi.buildInputs = [ mpi ];
  graph_parallel.buildInputs = [ mpi ];
  property_map_parallel.buildInputs = [ mpi ];

  python = {
    buildInputs = [ python3 ];
    cmakeFlags = [ (lib.cmakeFeature "Python_EXECUTABLE" (lib.getExe python3)) ];
  };

  parameter_python = {
    buildInputs = [ python3 ];
    cmakeFlags = [ (lib.cmakeFeature "Python_EXECUTABLE" (lib.getExe python3)) ];
  };
}
