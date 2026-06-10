{ stdenvNoCC, fetchurl }:
stdenvNoCC.mkDerivation rec {
  pname = "slk";
  version = "0.8.11";

  src = fetchurl {
    url = "https://github.com/gammons/slk/releases/download/v${version}/slk_${version}_darwin_arm64.tar.gz";
    sha256 = "0qaj7n5akia78a21hx83lc4amanjasmp2iimqqaf3ywb02ka1x3q";
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 slk $out/bin/slk
    runHook postInstall
  '';
}
