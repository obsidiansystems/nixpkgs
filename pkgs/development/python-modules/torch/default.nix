{ stdenv
, python
, buildPythonPackage
, fetchurl
, isPy27, isPy35, isPy36
, numpy
, scipy
, pyyaml
, gcc
, cudaSupport ? false
, cudaVersion ? null
, cudatoolkit ? null
, cudnn ? null
, linuxPackages ? null
}:

assert cudaSupport -> cudaVersion != null
                   && cudatoolkit != null
                   && cudnn != null
                   && linuxPackages != null;

# unsupported combination
assert ! (stdenv.isDarwin && cudaSupport);

buildPythonPackage rec {
  pname = "torch";
  version = "0.1.12";
  name = "${pname}-${version}";
  format = "wheel";
  disabled = ! (isPy35 || isPy36 || isPy27);

  src =
    let osxUrlOf = pyFlavor:
          "http://download.pytorch.org/whl/torch-0.1.12.post2-${pyFlavor}-macosx_10_7_x86_64.whl";
        linuxUrlOf = cudaFlavor: pyFlavor:
          "http://download.pytorch.org/whl/${cudaFlavor}/torch-0.1.12.post2-${pyFlavor}-linux_x86_64.whl";
        dls = {
          darwin = {
            py27 = {
              url = osxUrlOf "cp27-none";
              sha256 = "0nm43ij9yzjrsc6ckw83wdpwvcfg9p9pq3hzgb1il2yqjfpx7ifs";
            };
            py35 = {
              url = osxUrlOf "cp35-cp35m";
              sha256 = "1kkwjys7a1w1krc0dg4klj3fnfsxx56q4iydn0130lfxl11ba48k";
            };
            py36 = {
              url = osxUrlOf "cp36-cp36m";
              sha256 = "0lw1dsm5l89zsd8z060mw7j5k4qn6z3rwbwjhs2y81qdgsbjs60n";
            };
          };
          linux = rec {
            cpu = cu75;
            cu75 = {
              py27 = {
                url = linuxUrlOf "cu75" "cp27-none";
                sha256 = "0a7smdi6257536rncr2alz3dshz91fmi86cbq6vswb9r7wfg6z0q";
              };
              py35 = {
                url = linuxUrlOf "cu75" "cp35-cp35m";
                sha256 = "0dfg443h94w0mjagm0lidfcqwk8iah7rdjrq35x7k9s3vcz7kinq";
              };
              py36 = {
                url = linuxUrlOf "cu75" "cp36-cp36m";
                sha256 = "1vnv3y57ih7f44bbi26sawssrk8k0rqlbpza9sw92idywgz7zbsx";
              };
            };
            cu80 = {
              py27 = {
                url = linuxUrlOf "cu80" "cp27-none";
                sha256 = "0xbax538ydzz3pw9rgr07f4krlh1cm4yxragk888m0rzxq1rlc73";
              };
              py35 = {
                url = linuxUrlOf "cu80" "cp35-cp35m";
                sha256 = "1qn3y9gxa1nfl9mrk3i63nnhi4ywsqlzbpw0mxvkd8ipq558h289";
              };
              py36 = {
                url = linuxUrlOf "cu80" "cp36-cp36m";
                sha256 = "0ryi3r1i80g9cnhfpdqsq9m6nwbyapc82sk0mwa259448cv793xf";
              };
            };
          };
        };
        dl = if stdenv.isDarwin then
               if isPy27 then
                 dls.darwin.py27
               else if isPy35 then
                 dls.darwin.py35
               else dls.darwin.py36
             else if cudaSupport then
               if cudaVersion == "cu75" then
                 if isPy27 then
                   dls.linux.cu75.py27
                 else if isPy35 then
                   dls.linux.cu75.py35
                 else dls.linux.cu75.py36
               else if isPy27 then
                 dls.linux.cu80.py27
               else if isPy35 then
                 dls.linux.cu80.py35
               else dls.linux.cu80.py36
             else if isPy27 then
               dls.linux.cpu.py27
             else if isPy35 then
               dls.linux.cpu.py35
             else dls.linux.cpu.py36;
    in fetchurl dl;

  propagatedBuildInputs = with stdenv.lib; [
    numpy
    scipy
    pyyaml
  ] ++ optionals cudaSupport [ cudatoolkit cudnn ];

  postFixup = let
    extraRPath = stdenv.lib.makeLibraryPath
      ( if cudaSupport then
          [ gcc.cc.lib cudatoolkit cudnn linuxPackages.nvidia_x11 ]
        else
          [ gcc.cc.lib ]);
  in '' for x in $(find $out -name '*.so*') ; do
          patchelf --set-rpath "${extraRPath}:$out/lib/${python.libPrefix}/site-packages/torch/lib" $x
        done
     '';

  meta = with stdenv.lib; {
    description = "Tensors and Dynamic neural networks in Python with strong GPU acceleration.";
    homepage = http://pytorch.org;
    license = licenses.bsd3;
    platforms = with platforms; if cudaSupport then linux else linux ++ darwin;
  };

  passthru.cudaSupport = true;
}
