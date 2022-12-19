{
  description = "pickaxe redmine wiki editor";
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-22.11";
    flake-utils.url = "flake-utils";
  };
  outputs = { self, nixpkgs, flake-utils }:
  flake-utils.lib.eachDefaultSystem (system:
    let pkgs = nixpkgs.legacyPackages.${system}; in
    {
      packages.default = with pkgs; stdenv.mkDerivation {
        name = "pickaxe";
        src = self;
        buildInputs = [ makeWrapper ];
        installPhase = ''
          mkdir -p $out
          cp -r bin lib $out/
        '';
        postFixup = ''
          wrapProgram $out/bin/pickaxe --set PERL5LIB ${with perlPackages; makeFullPerlPath [ Mojolicious Curses IOSocketSSL AlgorithmDiff ]}:$out/lib
        '';
      };
    });
}
