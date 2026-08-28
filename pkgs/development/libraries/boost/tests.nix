# Checks the two things about this split that are easy to break silently.
#
# The first is that a library's siblings resolve at runtime: they are linked by
# soname as they always were, but they now live in their own store paths rather
# than beside it, so nothing but the runtime search path makes that work.
#
# The second is the closure. Depending on one library is supposed to bring in
# that library and its dependencies and nothing else -- that is the whole point
# of the split, and a stray reference would undo it without breaking a build.
{
  lib,
  runCommandCC,
  boostPackages,
}:

runCommandCC "boost-split-test"
  {
    buildInputs = with boostPackages; [
      context
      filesystem
    ];

    meta = {
      description = "Check that Boost libraries resolve each other across store paths";
    };
  }
  (
    ''
      cat > test.cc <<EOF
      #include <boost/filesystem.hpp>
      #include <boost/context/fiber.hpp>
      #include <iostream>

      int main() {
        boost::context::fiber f{[](boost::context::fiber && c) {
          std::cout << boost::filesystem::current_path().string() << std::endl;
          return std::move(c);
        }};
        std::move(f).resume();
        return 0;
      }
      EOF
    ''
    # Boost.Filesystem needs Boost.Atomic, which is a package of its own now:
    # this only runs if the sibling libraries are on the runtime search path.
    + ''
      $CXX -std=c++20 test.cc -lboost_filesystem -lboost_context -o test
      ./test
    ''
    # Nothing that is not Boost, libc or libstdc++ belongs here. icu4c in
    # particular is what made the split worth doing.
    # https://github.com/NixOS/nixpkgs/issues/45462
    + ''
      if ldd ./test | grep -E 'icu|libz\.|libbz2|liblzma|libzstd'; then
        echo "an unrelated library leaked into the closure" >&2
        exit 1
      fi

      touch $out
    ''
  )
