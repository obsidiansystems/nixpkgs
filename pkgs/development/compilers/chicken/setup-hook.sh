addChickenRepositoryPath() {
    appendToSearchPathWithCustomDelimiter : CHICKEN_REPOSITORY_EXTRA "$1/lib/chicken/8/"
    # appendToSearchPathWithCustomDelimiter \; CHICKEN_INCLUDE_PATH "$1/share/"
    export CHICKEN_INCLUDE_PATH="$1/share;$CHICKEN_INCLUDE_PATH"
}

envHooks=(${envHooks[@]} addChickenRepositoryPath)
