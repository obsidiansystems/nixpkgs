declare -A boostPathsSeen

_addToBoostPath() {
    local dir="$1"
    # Stop if we've already visited here.
    [[ -z "${boostPathsSeen[$dir]}" ]] || return 0
    boostPathsSeen[$dir]=1

    case "$dir" in
        *-dev) addToSearchPathWithCustomDelimiter ' ' BOOST_INCLUDEDIR "$dir/include" ;;
        *)     addToSearchPathWithCustomDelimiter ' ' BOOST_LIBDIR "$dir/lib" ;;
    esac

    local prop="$dir/nix-support/propagated-build-inputs"
    # Inspect the propagated inputs (if they exist) and recur on them.
    if [ -e "$prop" ]; then
        local new_path
        for new_path in $(< "$prop"); do
            _addToBoostPath "$new_path"
        done
    fi
}

_addToBoostPath @dev@

if [ -Z "$NIX_DEBUG" ]; then unset -f _addToBoostPath; fi
