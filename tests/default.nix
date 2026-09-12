{ sources ? import ./nix/sources.nix
, pkgs ? import sources.nixpkgs {}
}:

pkgs.mkShell {
  buildInputs = [
    pkgs.mpv
    pkgs.ffmpeg
    pkgs.xorg.xorgserver
    pkgs.xdotool
    pkgs.lua
    pkgs.luaPackages.moonscript
    pkgs.python39
  ];
}