grantleePluginPrefix=@grantleePluginPrefix@

providesGrantleeRuntime() {
    [ -d "$1/$grantleePluginPrefix" ]
}

_grantleeCrossEnvHook() {
    if providesQtRuntime "$1"; then
        propagatedBuildInputs+=" $1"
        propagatedUserEnvPkgs+=" $1"
    fi
}
addEnvHooks "$hostOffset" _grantleeCrossEnvHook
