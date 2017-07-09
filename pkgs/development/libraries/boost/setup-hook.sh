_addToBoostPath() {
    local dir="$1"
    # Stop if we've already visited here.
    if [ -n "${boostPathsSeen[$dir]}" ]; then return; fi
    boostPathsSeen[$dir]=1

    case "$dir" in
        *-dev) addToSearchPathWithCustomDelimiter ' ' BOOST_INCLUDEDIR "$dir/include" ;;
        *)     addToSearchPathWithCustomDelimiter ' ' BOOST_LIBDIR "$dir/lib" ;;
    esac

    # Inspect the propagated inputs (if they exist) and recur on them.
    local prop="$dir/nix-support/propagated-build-inputs"
    if [ -e $prop ]; then
        local new_path
        while IFS= read -r new_path; do
            _addToBoostPath $new_path
        done < $prop
    fi
}

_addToBoostPath() @dev@

if [ -Z "$NIX_DEBUG" ]; unset -f _addToBoostPath; fi
