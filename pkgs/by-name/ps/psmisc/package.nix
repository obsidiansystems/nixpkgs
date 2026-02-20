{
  lib,
  stdenv,
  fetchFromGitLab,
  fetchpatch,
  autoconf,
  automake,
  gettext,
  ncurses,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "psmisc";
  version = "23.7";

  src = fetchFromGitLab {
    owner = "psmisc";
    repo = "psmisc";
    rev = "v${finalAttrs.version}";
    hash = "sha256-49YpdIh0DxLHfxos4sw1HUkV0XQBqmm4M9b0T4eN2xI=";
  };

  nativeBuildInputs = [
    autoconf
    automake
    gettext
  ];
  buildInputs = [ ncurses ];

  patches = lib.optionals stdenv.hostPlatform.isFreeBSD [
    ./freebsd.patch
    (fetchpatch {
      url = "https://gitlab.com/psmisc/psmisc/-/commit/dd9b91670ab2cf618e619b59aec62a73446a1da9.patch";
      hash = "sha256-6y7WQWpK8NOq2EBsiAOcV1WXED8DvYU9daVXBAJJrDk=";
    })
  ];
  configureFlags = lib.optionals stdenv.hostPlatform.isFreeBSD [ "--disable-statx" ];

  preConfigure =
    lib.optionalString (stdenv.buildPlatform != stdenv.hostPlatform) ''
      # Goes past the rpl_malloc linking failure
      export ac_cv_func_malloc_0_nonnull=yes
      export ac_cv_func_realloc_0_nonnull=yes
    ''
    + ''
      echo $version > .tarball-version
      ./autogen.sh
    '';

  meta = {
    homepage = "https://gitlab.com/psmisc/psmisc";
    description = "Set of small useful utilities that use the proc filesystem (such as fuser, killall and pstree)";
    platforms = lib.platforms.linux ++ lib.platforms.freebsd;
    license = lib.licenses.gpl2Plus;
    maintainers = with lib.maintainers; [ ryantm ];
  };
})
