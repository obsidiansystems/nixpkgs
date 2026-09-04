# Compiler wrappers and bootstrapping stages {#chap-wrappers}

## Introduction {#sec-wrappers-intro}

Nixpkgs does not call a compiler directly. Every C compiler and every set of binutils a package sees is a *wrapper*: a shell script that adds the flags a build needs to find its libc, its C++ standard library, and its compiler runtime, and that keeps a build from reaching outside the Nix store. The wrapper is small, but it sits at an awkward point in the dependency graph, and this chapter is about that point.

Wrappers are needed for two reasons, and it helps to keep them apart.

The first is that Nixpkgs builds *separately* what most distributions build *together*. A conventional toolchain build produces the compiler, its runtime library, the C++ standard library and often the libc in one go, and the resulting compiler knows where its libraries are because they were installed next to it. Nixpkgs builds each of those as its own package, with its own store path, so that a compiler can be paired with more than one libc, a libc can be built by more than one compiler, and nothing is rebuilt twice for want of a place to put it. Something then has to tell the compiler where its pieces went. That is the wrapper.

The second reason is that those pieces come from *different stages*. The [cross-compilation chapter](#chap-cross) describes how Nixpkgs is built up in stages, each stage a complete package set built with the previous one. The rules that make stages work are simple:

- A dependency used at build time is *native*: it runs on the build platform. It comes from the previous stage.
- A dependency used at run time is *foreign*: it runs on the host platform. It comes from the same stage as the package using it.
- A run-time dependency of a build-time dependency is, transitively, a build-time dependency.

Put together: a run-time dependency is a same-stage dependency, a build-time dependency is a previous-stage dependency, and a package never depends on a *future* stage. Almost every package in Nixpkgs is fine with this. A compiler wrapper is where the two kinds of dependency have to be mixed together, and it is the one place where the mixing is unavoidable.

## Why wrappers are the exception {#sec-wrappers-exception}

A compiler wrapper injects dependencies into the artifacts the compiler produces. When a package is linked, the libc, the C++ library, and the compiler runtime it gets are whatever the wrapper points at. Those libraries run on the host platform of the *package being built*: they are run-time dependencies of the package, not of the compiler. But the compiler itself runs on the build platform, one stage earlier. So the wrapper straddles two stages: it is a build-time tool that has to know about run-time libraries.

There are two places the wrapping can happen, and they are not equivalent.

If the stage that *builds* a compiler also wraps it, the wrapper has to reach *forward* for libraries that belong to the next stage. Historically Nixpkgs did this. `targetPackages`, the package set for the stage after this one, exists largely to make that reach possible, and much of the `targetPlatform` machinery exists to key selections on it. A forward reach is a *layer violation*: a stage is supposed to be a function of the stages before it, and a bootstrapping chain that reads what comes *after* a stage is sensitive to it, which is the opposite of what bootstrapping wants. The last stage has no successor at all, so a stub had to stand in for it.

If instead the stage that *uses* a compiler wraps it, nothing reaches forward. The libc and the C++ library are simply packages in the same stage as the wrapper, the platform to key on is the stage's own `hostPlatform`, and the compiler binary comes from the previous stage like any other build-time dependency. Removing the layer violation is exactly why the wrapping happens "one stage later" than the compiler is built. This is what Nixpkgs does now.

The principle behind both this chapter and the cross-compilation one is that a package should be legible in isolation: it should never have to know how many compilers the bootstrap needs, which of them builds a library, or whether it is being cross-compiled. The `stdenv.cc` it is handed is always a toolchain that targets the platform the package is being built for, and that is all it needs to know. Wrapping in the consuming stage is what makes that promise cheap to keep.

## `_tools`: the toolchain a stage was handed {#sec-wrappers-tools}

Every package set has an attribute `_tools`. It is the toolchain the stage was given by the stage before it, wrapped in this stage, and it is what `stdenv` is built from. The definition lives in `pkgs/top-level/stage-tools.nix`; the leading underscore marks it as bootstrapping machinery rather than a package to reach for by hand.

It has a fixed shape:

`cc-unwrapped`, `bintools-unwrapped`

: The compiler and binutils binaries, built by the previous stage. They target this stage's host platform because that was the previous stage's target platform.

`cc`, `bintools`

: The same, wrapped here, against this stage's libc. `stdenv.cc` is `_tools.cc`.

`bintoolsNoLibc`

: Binutils wrapped against the pre-libc headers only, for building a libc.

`ccNoLibc`

: A compiler with its runtime but no libc, for building a libc.

`ccNoLibs`

: A compiler with neither, for building the compiler runtime itself.

`wrapCCWith`, `wrapBintoolsWith`

: The wrapping functions. They come from the previous stage (the wrapper is a script that runs on the build platform, and it is `callPackage`, not the `stdenvNoCC` argument, that decides which stage a wrapper's own dependencies come from) but they wrap *for* this stage.

`sdk`

: On Darwin, the SDK. It is part of what a stage is handed, alongside the compiler, and `stdenv` needs it in `extraBuildInputs`.

Which toolchain fills these in is a single switch on the host platform: LLVM if `useLLVM` or Darwin, the GCC-NG split set if `useGccNG`, Zig if `useZig`, Arocc if `useArocc`, and monolithic GCC otherwise. There used to be three copies of that switch, one each for `stdenv.cc`, `stdenvNoLibs` and `stdenvNoLibc`, and they could drift. Now the switch picks a toolchain and every rung is taken from it.

### The same shape on every toolchain {#ssec-wrappers-toolchain-tools}

`llvmPackages`, `gccNGPackages`, `zig`, and `aroccPackages` each expose their own `_tools`, in the same shape, drawn from *their* previous-stage counterpart (`buildLlvmPackages`, `buildGccPackages`, `buildPackages.zig`, and so on). The top-level `_tools` selects one of them. This is where all of a toolchain's wrapping now lives: `llvmPackages._tools` holds every `clang` variant, wrapped against this stage's `libcxx` and `compiler-rt`; `gccNGPackages._tools` holds every rung of the GCC-NG bootstrap ladder, wrapped against this stage's `libgcc`, `libstdcxx`, `libssp`, `libatomic` and `libgomp`.

Not every toolchain can offer every rung. LLVM and the GCC-NG split set can express "no compiler runtime at all" and "compiler runtime but no libc" separately, because they build those pieces separately: the compiler is a tool, the runtime libraries are ordinary packages, and the dependencies between them criss-cross without ever forming a cycle. Monolithic GCC cannot, so one compiler serves both. Zig ships its own libc and runtime, so it has nothing to reduce and its `cc` serves all three. Each set says so in its own file, and the top-level switch does not need to know.

### `_tools` in a package {#ssec-wrappers-tools-spliced}

A package that takes `_tools` as a `callPackage` argument gets it *spliced*, like any other package set, but off by one. A set's `_tools` is the toolchain it was handed: it runs on the set's build platform and targets the set's host platform. So the toolchain that runs on the build platform and targets the package's host, which is what a `nativeBuildInputs` entry needs, is this very set's `pkgs._tools`, and the toolchain that runs on the package's host is `targetPackages._tools`. `pkgs/top-level/splice.nix` fills the `__spliced` slots that way for `_tools` alone, and `makeScopeWithSplicing'` inherits it, so `llvmPackages._tools` and the other toolchain sets behave the same. Read directly, without going through the splicer, `_tools.cc` is this stage's compiler, the same one `stdenv.cc` is. In the final stage of a cross bootstrap there is no `targetPackages._tools`, and the slot is simply absent.

`pkgs._tools`, by contrast, is never spliced: it is this stage's toolchain as plain derivations. That is what the bootstrapping plumbing reads (`stage-tools.nix`, the bootstrap files, the toolchain sets), because it passes those entries on into wrappers and dependency lists, where a spliced derivation would have the splicer swap in the next stage's.

## What a stage provides {#sec-wrappers-invariant}

The rule that follows from all of this is short: **ignoring `_tools`, a stage provides only unwrapped tools.** `gcc15-unwrapped`, `llvmPackages.clang-unwrapped`, `binutils-unwrapped`, `zig.cc-unwrapped` are real packages built by the stage. Everything wrapped lives in some `_tools` and is wrapped there. There is no `wrapCCWith` call in Nixpkgs outside a `_tools`.

The old wrapped names (`gcc`, `gcc15`, `clang`, `llvmPackages.clang`, `bintools`, `binutils`, `wrapCCWith`, `wrapCC`, `wrapBintoolsWith`, `zig.cc`, and so on) still exist, as aliases. They are what a stage used to hand to its successor, and what a stage hands to its successor is exactly that successor's `_tools`, so they are defined as `targetPackages._tools.<name>` (or `targetLlvmPackages._tools.<name>` inside `llvmPackages`, and so on). They only exist where there *is* a successor: a stage that builds for itself is its own successor and keeps them, which is why `nix-build -A gcc` still works, but the final stage of a cross bootstrap has none and skips them. Like every alias they disappear when `config.allowAliases` is false, which is how the rule above is checked.

## Bootstrapping {#sec-wrappers-bootstrapping}

A bootstrapping stage, one of the functions in `pkgs/stdenv/linux/default.nix`, `pkgs/stdenv/darwin/default.nix` and their siblings, provides two things to `pkgs/top-level/stage.nix`:

- `stdenvNoCC`: the standard environment without a compiler.
- `bootstrapOverlays`: an overlay setting `_tools` to the toolchain this stage was handed: `cc`, usually `bintools`, and on Darwin `sdk`.

`stage.nix` derives `stdenv` from the two: `stdenvNoCC` with `_tools.cc` put back in, and on Darwin the SDK restored to `extraBuildInputs`. Everything else that used to be baked into a passed `stdenv` (the compiler choice, the platform to key on, which libc to wrap against) is now either in `_tools` or derivable from `hostPlatform`.

`bootstrapOverlays` is separate from `overlays` on purpose. A stage's `overlays` are handed on verbatim to every re-bootstrapped package set (`pkgsMusl`, `pkgsStatic`, `pkgsCross.*`, and so on), which build their own chains and must not inherit a toolchain from this one. `bootstrapOverlays` stay with the stage.

The stages are chained by `pkgs/stdenv/booter.nix`. Each stage sees only its predecessor; the booter tells the final one that it is final, so that it does not look for a successor. There is no longer a fabricated stage after the last one.

Three things to keep in mind when writing or reading a bootstrap stage:

- Inside a stage, use the in-stage names. `binutils` is the binutils this stage built; `bintools` is an alias that reaches forward through `targetPackages`, and in a bootstrapping chain that reach can resolve differently depending on what follows the stage.
- A newly built compiler is never run in the same stage that built it. It is handed forward, as `*-unwrapped`, and the next stage wraps it and uses it. This is what keeps a stage a function of its predecessors, and it is why no stage builds anything with its own output.
- The "impure" native stages, which use the tools of the host system, supply a wrapper with `nativeTools = true` as their `_tools.cc`. That is the general mechanism, not a special case: whatever a stage was handed, it says so in `_tools`.

The user-facing hooks `config.replaceStdenv` and `config.replaceCrossStdenv` take and return a whole `stdenv`. They still pass it as the deprecated `stdenv` argument of `stage.nix`, which is kept for them.

## History {#sec-wrappers-history}

Nixpkgs got here in steps. In 2009 there were per-platform packages like `binutilsMips`; then there were `*Cross` variants of tools that every package had to choose between, which put the bootstrapping decision inside packages; the 2017 cross-compilation overhaul removed those by having `stdenv` provide the right variant, and the remaining `libcCross` workarounds went in 2024 and 2025.

This design is the one from the 2016 "Sane cross-compiling through bootstrapping" work, `pkgs/top-level/build-wrappers.nix`, turned around. That file put all the wrappers in one place for the same reasons given above, and made them available only through `buildPackages`; but it resolved the two-stage problem by reaching *forward*, into `__targetPackages`. `_tools` reaches *back*. The dependency then runs the same direction as every other build-time dependency, there is no future stage to name, and `targetPackages` and `targetPlatform` are no longer needed for it.
