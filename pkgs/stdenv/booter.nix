# This file defines a single function for booting a package set from a list of
# stages. The exact mechanics of that function are defined below; here I
# (@Ericson2314) wish to describe the purpose of the abstraction.
#
# The first goal is consistency across stdenvs. Regardless of what this function
# does, by making every stdenv use it for bootstrapping we ensure that they all
# work in a similar way. [Before this abstraction, each stdenv was its own
# special snowflake due to different authors writing in different times.]
#
# The second goal is consistency across each stdenv's stage functions. By
# writing each stage in terms of the previous stage, commonalities between them
# are more easily observable. [Before, there usually was a big attribute set
# with each stage, and stages would access the previous stage by name.]
#
# The third goal is composition. Because each stage is written in terms of the
# previous, the list can be reordered or, more practically, extended with new
# stages. The latter is used for cross compiling and custom
# stdenvs. Additionally, certain options should by default apply only to the
# last stage, whatever it may be. By delaying the creation of stage package sets
# until the final fold, we prevent these options from inhibiting composition.
#
# The fourth and final goal is debugging. Normal packages should only source
# their dependencies from the current stage. But for the sake of debugging, it
# is nice that all packages still remain accessible. We make sure previous
# stages are kept around with a `stdenv.__bootPackages` attribute referring the
# previous stage. It is idiomatic that attributes prefixed with `__` come with
# special restrictions and should not be used under normal circumstances.
{ lib, allPackages }:

# Type:
#   [ pkgset -> (args to stage/default.nix) or ({ __raw = true; } // pkgs) ]
#   -> pkgset
#
# In English: This takes a list of function from the previous stage pkgset and
# returns the final pkgset. Each of those functions returns, if `__raw` is
# undefined or false, args for this stage's pkgset (the most complex and
# important arg is the stdenv), or, if `__raw = true`, simply this stage's
# pkgset itself.
#
# The list takes stages in order, so the final stage is last in the list. In
# other words, this does a foldr not foldl.
stageFuns:
let

  /*
    "dfold" a ternary function `op' between successive elements of `list' as if
    it was a doubly-linked list with `lnul' and `rnul` base cases at either
    end. In precise terms, `dfold op lnul rnul [x_0 x_1 x_2 ... x_n-1]` is the
    same as

      let
        f_-1  = lnul f_0;
        f_0   = op f_-1   x_0  f_1;
        f_1   = op f_0    x_1  f_2;
        f_2   = op f_1    x_2  f_3;
        ...
        f_n   = op f_n-1  x_n  f_n+1;
        f_n+1 = rnul f_n;
      in
        f_0
  */
  # `op` additionally receives whether its element is `x_0`, the one next to
  # `lnul`; for the bootstrap fold that is the final stage.
  dfold =
    op: lnul: rnul: list:
    let
      len = builtins.length list;
      go =
        pred: n:
        if n == len then
          rnul pred
        else
          let
            # Note the cycle -- call-by-need ensures finite fold.
            cur = op (n == 0) pred (builtins.elemAt list n) succ;
            succ = go cur (n + 1);
          in
          cur;
      lapp = lnul cur;
      cur = go lapp 0;
    in
    cur;

  # Take the list and disallow custom overrides in all but the final stage,
  # and allow it in the final flag. Only defaults this boolean field if it
  # isn't already set.
  withAllowCustomOverrides = lib.lists.imap1 (
    index: stageFun: prevStage:
    # So true by default for only the first element because one
    # 1-indexing. Since we reverse the list, this means this is true
    # for the final stage.
    { allowCustomOverrides = index == 1; } // (stageFun prevStage)
  ) (lib.lists.reverseList stageFuns);

  # Sticks the previous and next stages into the stdenv, for debugging. A stage
  # provides either `stdenvNoCC` (plus a `_tools` overlay) or, deprecated, the
  # full `stdenv`; whichever it is gets the bookkeeping, and `stage.nix` carries
  # it onto the `stdenv` it derives.
  folder =
    isFinal: nextStage: stageFun: prevStage:
    let
      args = stageFun prevStage;
      bookkeeping = {
        __bootPackages = prevStage;
        __hatPackages = nextStage;
      };
      args' =
        args
        // lib.optionalAttrs (args ? stdenv) { stdenv = args.stdenv // bookkeeping; }
        // lib.optionalAttrs (args ? stdenvNoCC) { stdenvNoCC = args.stdenvNoCC // bookkeeping; };
      # Platforms are the same on both; read them from whichever was given.
      platforms = args.stdenvNoCC or args.stdenv;
      thisStage =
        if args.__raw or false then
          args'
        else
          allPackages (
            (removeAttrs args' [ "selfBuild" ])
            // {
              # The final stage has no successor to hand a toolchain to; `stage.nix`
              # drops the deprecated wrapped-tool names there (the empty sentinel
              # from `dfold` is its `pkgsTargetTarget`).
              isFinalStage = isFinal;
              adjacentPackages =
                if args.selfBuild or true then
                  null
                else
                  rec {
                    pkgsBuildBuild = prevStage.buildPackages;
                    pkgsBuildHost = prevStage;
                    pkgsBuildTarget =
                      if platforms.targetPlatform == platforms.hostPlatform then
                        pkgsBuildHost
                      else
                        assert platforms.hostPlatform == platforms.buildPlatform;
                        thisStage;
                    pkgsHostHost =
                      if platforms.hostPlatform == platforms.targetPlatform then
                        thisStage
                      else
                        assert platforms.buildPlatform == platforms.hostPlatform;
                        pkgsBuildHost;
                    pkgsTargetTarget = nextStage;
                  };
            }
          );
    in
    thisStage;

  pkgs = dfold folder (_: { }) (_: { }) withAllowCustomOverrides;

in
# Return the spliced package set, so that consumers of the nixpkgs top-level
# attributes, like NixOS, don't break when cross-compiling.
pkgs.__splicedPackages
