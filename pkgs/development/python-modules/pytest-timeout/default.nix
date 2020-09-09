{ buildPythonPackage
, fetchPypi
, fetchpatch
, lib
, pexpect
, pytest
}:

buildPythonPackage rec {
  pname = "pytest-timeout";
  version = "1.3.4";

  src = fetchPypi {
    inherit pname version;
    sha256 = "13n42azbvs5slvy2n1a9nw17r4qdq10dd68nln3jp925safa3yl0";
  };

  checkInputs = [ pytest pexpect ];
  checkPhase = ''
    # test_suppresses_timeout_when_pdb_is_entered fails under heavy load
    pytest -ra -k 'not test_suppresses_timeout_when_pdb_is_entered'
  '';

  meta = with lib;{
    description = "py.test plugin to abort hanging tests";
    homepage = https://bitbucket.org/pytest-dev/pytest-timeout/;
    license = licenses.mit;
    maintainers = with maintainers; [ makefu costrouc ];
  };
}
