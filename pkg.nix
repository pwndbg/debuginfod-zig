{
  lib,
  stdenv,
  fetchFromGitHub,
  zig_0_14,

  # Others
  zigRequired,
  flags,
}:
let
  target =
    if stdenv.hostPlatform.isLinux then
      "-Dtarget=native-linux-gnu.2.28"
    else
      "-Dtarget=native-macos.${stdenv.hostPlatform.darwinSdkVersion}";
in
stdenv.mkDerivation {
  name = "debuginfod-zig";
  version = "0.194";

  src = ./.;

  zigBuildFlags = [
    target
  ]
  ++ flags;

  nativeBuildInputs = [
    (zig_0_14.hook.override { zig = zigRequired; })
  ];
}
