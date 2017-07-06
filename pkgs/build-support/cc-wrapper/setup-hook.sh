if [ -z "$crossConfig" ]; then
  ENV_PREFIX=""
else
  ENV_PREFIX="BUILD_"
fi

# We need to mangle names for hygiene, but also take parameters/overrides from
# the environment
slurpUnsalted () {
    local varname="$1"
    local inputVar="NIX_${ENV_PREFIX}${varname}"
    appendDelimit ' ' "NIX_@infixSalt@_${varname}" "${!inputVar}"
}

slurpUnsalted CFLAGS_COMPILE
slurpUnsalted CFLAGS_LINK
slurpUnsalted GNATFLAGS_COMPILE
slurpUnsalted LDFLAGS
slurpUnsalted LDFLAGS_BEFORE
slurpUnsalted LDFLAGS_AFTER
slurpUnsalted LDFLAGS_HARDEN

slurpUnsalted SET_BUILD_ID
slurpUnsalted DONT_SET_RPATH
slurpUnsalted ENFORCE_NO_NATIVE

addCVars_@infixSalt@ () {
    if [ -d $1/include ]; then
        export NIX_@infixSalt@_CFLAGS_COMPILE+=" ${ccIncludeFlag:--isystem} $1/include"
    fi

    if [ -d $1/lib64 -a ! -L $1/lib64 ]; then
        export NIX_@infixSalt@_LDFLAGS+=" -L$1/lib64"
    fi

    if [ -d $1/lib ]; then
        export NIX_@infixSalt@_LDFLAGS+=" -L$1/lib"
    fi

    if test -d $1/Library/Frameworks; then
        export NIX_@infixSalt@_CFLAGS_COMPILE="$NIX_@infixSalt@_CFLAGS_COMPILE -F$1/Library/Frameworks"
    fi
}

envHooks+=(addCVars_@infixSalt@)

# Note: these come *after* $out in the PATH (see setup.sh).

if [ -n "@cc@" ]; then
    addToSearchPath _PATH @cc@/bin
fi

if [ -n "@binutils_bin@" ]; then
    addToSearchPath _PATH @binutils_bin@/bin
fi

if [ -n "@libc_bin@" ]; then
    addToSearchPath _PATH @libc_bin@/bin
fi

if [ -n "@coreutils_bin@" ]; then
    addToSearchPath _PATH @coreutils_bin@/bin
fi

export NIX_${ENV_PREFIX}CC=@out@

export ${ENV_PREFIX}CC=@named_cc@
export ${ENV_PREFIX}CXX=@named_cxx@

for CMD in \
    cpp \
    ar as nm objcopy ranlib strip strings size ld windres
do
    if
        PATH=$_PATH type -p "@binPrefix@$CMD" > /dev/null
    then
        export "${ENV_PREFIX}$(echo "$CMD" | tr "[:lower:]" "[:upper:]")=@binPrefix@${CMD}";
    fi
done

# No local scope available for sourced files
unset ENV_PREFIX
