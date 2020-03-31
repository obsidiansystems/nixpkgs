{ stdenv, fetchurl, gfortran, readline, ncurses, perl, flex, texinfo, qhull
, libsndfile, portaudio, libX11, graphicsmagick, pcre, pkgconfig, libGL, libGLU, fltk
, fftw, fftwSinglePrec, zlib, curl, qrupdate, blas, lapack, arpack, libwebp, gl2ps
, qt ? null, qscintilla ? null, ghostscript ? null, llvm ? null, hdf5 ? null,glpk ? null
, suitesparse ? null, gnuplot ? null, jdk ? null, python ? null, overridePlatforms ? null
}:

assert (!blas.is64bit) && (!lapack.is64bit);

stdenv.mkDerivation rec {
  version = "5.2.0";
  pname = "octave";
  src = fetchurl {
    url = "mirror://gnu/octave/${pname}-${version}.tar.gz";
    sha256 = "1qcmcpsq1lfka19fxzvxjwjhg113c39a9a0x8plkhvwdqyrn5sig";
  };

  buildInputs = [ gfortran readline ncurses perl flex texinfo qhull
    graphicsmagick pcre pkgconfig fltk zlib curl blas lapack libsndfile fftw
    fftwSinglePrec portaudio qrupdate arpack libwebp gl2ps ]
    ++ (stdenv.lib.optional (qt != null) qt)
    ++ (stdenv.lib.optional (qscintilla != null) qscintilla)
    ++ (stdenv.lib.optional (ghostscript != null) ghostscript)
    ++ (stdenv.lib.optional (llvm != null) llvm)
    ++ (stdenv.lib.optional (hdf5 != null) hdf5)
    ++ (stdenv.lib.optional (glpk != null) glpk)
    ++ (stdenv.lib.optional (suitesparse != null) suitesparse)
    ++ (stdenv.lib.optional (jdk != null) jdk)
    ++ (stdenv.lib.optional (gnuplot != null) gnuplot)
    ++ (stdenv.lib.optional (python != null) python)
    ++ (stdenv.lib.optionals (!stdenv.isDarwin) [ libGL libGLU libX11 ])
    ;

  # makeinfo is required by Octave at runtime to display help
  prePatch = ''
    substituteInPlace libinterp/corefcn/help.cc \
      --replace 'Vmakeinfo_program = "makeinfo"' \
                'Vmakeinfo_program = "${texinfo}/bin/makeinfo"'
  '';

  doCheck = !stdenv.isDarwin;

  enableParallelBuilding = true;

  # See https://savannah.gnu.org/bugs/?50339
  F77_INTEGER_8_FLAG = if blas.is64bit then "-fdefault-integer-8" else "";

  configureFlags = [
    "--with-blas=blas"
    "--with-lapack=lapack"
    (if blas.is64bit then "--enable-64" else "--disable-64")
  ]
    ++ (if stdenv.isDarwin then [ "--enable-link-all-dependencies" ] else [ ])
    ++ stdenv.lib.optionals enableReadline [ "--enable-readline" ]
    ++ stdenv.lib.optionals stdenv.isDarwin [ "--with-x=no" ]
    ++ stdenv.lib.optionals enableQt [ "--with-qt=5" ]
    ++ stdenv.lib.optionals enableJIT [ "--enable-jit" ]
  ;

  # Keep a copy of the octave tests detailed results in the output
  # derivation, because someone may care
  postInstall = ''
    cp test/fntests.log $out/share/octave/${pname}-${version}-fntests.log || true
  '';

  passthru = {
    inherit version;
    sitePath = "share/octave/${version}/site";
  };

  meta = {
    homepage = "https://www.gnu.org/software/octave/";
    license = stdenv.lib.licenses.gpl3Plus;
    maintainers = with stdenv.lib.maintainers; [raskin];
    description = "Scientific Pragramming Language";
    platforms = if overridePlatforms == null then
      (with stdenv.lib.platforms; linux ++ darwin)
    else overridePlatforms;
  };
}
