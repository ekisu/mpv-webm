{ sources ? import ./nix/sources.nix
, pkgs ? import sources.nixpkgs {}
}:

pkgs.mkShell {
  buildInputs = [
    pkgs.mpv
    pkgs.lua
    pkgs.luaPackages.moonscript
    pkgs.python39
  ];
}