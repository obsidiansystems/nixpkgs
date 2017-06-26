# `-B@out@/bin' forces cc to use ld-wrapper.sh when calling ld.
export NIX_@infixSalt@_CFLAGS_COMPILE="-B@out@/bin/ $NIX_@infixSalt@_CFLAGS_COMPILE"

if [ -e @out@/nix-support/libc-cflags ]; then
    export NIX_@infixSalt@_CFLAGS_COMPILE="$(cat @out@/nix-support/libc-cflags) $NIX_@infixSalt@_CFLAGS_COMPILE"
fi

if [ -e @out@/nix-support/cc-cflags ]; then
    export NIX_@infixSalt@_CFLAGS_COMPILE="$(cat @out@/nix-support/cc-cflags) $NIX_@infixSalt@_CFLAGS_COMPILE"
fi

if [ -e @out@/nix-support/gnat-cflags ]; then
    export NIX_@infixSalt@_GNATFLAGS_COMPILE="$(cat @out@/nix-support/gnat-cflags) $NIX_@infixSalt@_GNATFLAGS_COMPILE"
fi

if [ -e @out@/nix-support/libc-ldflags ]; then
    export NIX_@infixSalt@_LDFLAGS+=" $(cat @out@/nix-support/libc-ldflags)"
fi

if [ -e @out@/nix-support/cc-ldflags ]; then
    export NIX_@infixSalt@_LDFLAGS+=" $(cat @out@/nix-support/cc-ldflags)"
fi

if [ -e @out@/nix-support/libc-ldflags-before ]; then
    export NIX_@infixSalt@_LDFLAGS_BEFORE="$(cat @out@/nix-support/libc-ldflags-before) $NIX_@infixSalt@_LDFLAGS_BEFORE"
fi

export NIX_@infixSalt@_CC_WRAPPER_FLAGS_SET=1
