{ stdenv
, buildPythonPackage
, fetchPypi
, ruamel_base
, ruamel_ordereddict
, isPy3k
}:

buildPythonPackage rec {
  pname = "ruamel.yaml.clib";
  version = "0.2.0";

  src = fetchPypi {
    inherit pname version;
    sha256 = "133igvb18g0gal4aks5n5pfbag970qysbi0iwgvb7nbph3m34s5n";
  };

  # outputs match wheel
  doCheck = false;

  meta = with stdenv.lib; {
    description = "YAML parser/emitter that supports roundtrip preservation of comments, seq/map flow style, and map key order";
    homepage = https://bitbucket.org/ruamel/yaml;
    license = licenses.mit;
  };

}
