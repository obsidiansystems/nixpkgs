{ stdenv, fetchFromGitHub, buildGoModule }:
buildGoModule rec {
  pname = "terraform-provider-shell";
  version = "1.6.0";

  src = fetchFromGitHub {
    owner = "scottwinkler";
    repo   = pname;
    rev    = "v${version}";
    sha256 = "0jxb30vw93ibnwz8nfqapac7p9r2famzvsf2h4nfbmhkm6mpan4l";
  };

  modSha256 = "0w99d5gp1dp4q8g5h6qx43f4ffdj4v8li996q86c8v4z0ij0jvg9";

  doCheck = false;

  subPackages = [ "." ];

  # Terraform allows checking the provider versions, but this breaks
  # if the versions are not provided via file paths.
  postInstall = "mv $out/bin/${pname}{,_v${version}}";

  meta = with stdenv.lib; {
    inherit (src.meta) homepage;
    description = "Terraform provider for executing shell commands and saving output to state file";
    changelog = "https://github.com/scottwinkler/terraform-provider-shell/releases/tag/v${version}";
    license = licenses.mpl20;
    maintainers = with maintainers; [ mupdt ];
  };
}
