{ lib, python, buildPythonPackage, fetchPypi, isPy27 }:

buildPythonPackage rec {
  pname = "scandir";
  version = "1.10.0";

  src = fetchPypi {
    inherit pname version;
    sha256 ="1bkqwmf056pkchf05ywbnf659wqlp6lljcdb0y88wr9f0vv32ijd";
  };

  checkPhase = "${python.interpreter} test/run_tests.py";

  # Broken:
  # OSError: [Errno 2] No such file or directory: '/build/scandir-1.10.0/test/testdir/linkdir/linksubdir'
  doCheck = !isPy27;

  meta = with lib; {
    description = "A better directory iterator and faster os.walk()";
    homepage = https://github.com/benhoyt/scandir;
    license = licenses.gpl3;
    maintainers = with maintainers; [ abbradar ];
  };
}
