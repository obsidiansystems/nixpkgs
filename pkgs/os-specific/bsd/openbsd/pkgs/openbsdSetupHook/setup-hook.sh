addOpenBSDMakeFlags() {
  makeFlags="INCSDIR=${!outputDev}/include $makeFlags"
}

fixOpenBSDInstallDirs() {
  find "$BSDSRCDIR" -name Makefile -exec \
    sed -i -E \
      -e 's|/usr/include|${INCSDIR}|' \
      -e 's|/usr/bin|${BINDIR}|' \
      -e 's|/usr/lib|${LIBDIR}|' \
      {} \;
}

noChownInstall() {
  find "$BSDSRCDIR" -name Makefile -exec \
    sed -i -E \
      -e 's|-o \$\{BINOWN\}||' \
      -e 's|-g \$\{BINGRP\}||' \
      {} \;
}

preConfigureHooks+=(addOpenBSDMakeFlags)
postPatchHooks+=(fixOpenBSDInstallDirs noChownInstall)
