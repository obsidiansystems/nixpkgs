# Binutils Wrapper hygiene
#
# See comments in cc-wrapper's setup hook. This works exactly the same way.

set -u

# Skip setup hook if we're neither a build-time dep, nor, temporarily, doing a
# native compile.
#
# TODO(@Ericson2314): No native exception
[[ -z ${crossConfig-} ]] || (( "$hostOffset" < 0 )) || return 0

binutilsWrapper_addLDVars () {
    case $depHostOffset in
        -1) local role='BUILD_' ;;
        0)  local role='' ;;
        1)  local role='TARGET_' ;;
        *)  echo "binutils-wrapper: Error: Cannot be used with $depHostOffset-offset deps" >2;
            return 1 ;;
    esac

    if [[ -d "$1/lib64" && ! -L "$1/lib64" ]]; then
        export NIX_${role}LDFLAGS+=" -L$1/lib64"
    fi

    if [[ -d "$1/lib" ]]; then
        export NIX_${role}LDFLAGS+=" -L$1/lib"
    fi
}

case $targetOffset in
    -1)
        export NIX_BINUTILS_WRAPPER_@infixSalt@_TARGET_BUILD=1
        role="BUILD_"
        ;;
    0)
        export NIX_BINUTILS_WRAPPER_@infixSalt@_TARGET_HOST=1
        role=""
        ;;
    1)
        export NIX_BINUTILS_WRAPPER_@infixSalt@_TARGET_TARGET=1
        role="TARGET_"
        ;;
    *)
        echo "cc-wrapper: used as improper sort of dependency" >2;
        return 1
        ;;
esac

addEnvHooks "$targetOffset" binutilsWrapper_addLDVars

# shellcheck disable=SC2157
if [ -n "@binutils_bin@" ]; then
    addToSearchPath _PATH @binutils_bin@/bin
fi

# shellcheck disable=SC2157
if [ -n "@libc_bin@" ]; then
    addToSearchPath _PATH @libc_bin@/bin
fi

# shellcheck disable=SC2157
if [ -n "@coreutils_bin@" ]; then
    addToSearchPath _PATH @coreutils_bin@/bin
fi

# Export tool environment variables so various build systems use the right ones.

export NIX_${role}BINUTILS=@out@

for CMD in \
    ar as nm objcopy objdump readelf ranlib strip strings size ld windres
do
    if
        PATH=$_PATH type -p "@binPrefix@$CMD" > /dev/null
    then
        export "${role}$(echo "$CMD" | tr "[:lower:]" "[:upper:]")=@binPrefix@${CMD}";
    fi
done

# No local scope in sourced file
unset role
set +u
