{ pkgs ? import <nixpkgs> {} }:

let
  # GitHub's servers will download this. Your Mac never sees it.
  xnu-1058-src = pkgs.fetchurl {
    url = "https://opensource.apple.com/tarballs/xnu/xnu-1228.tar.gz";
    sha256 = "sha256-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx="; # We will get the real hash
  };

  # Use Nix's built-in cross-compiler for PowerPC
  pkgsCross = import <nixpkgs> { crossSystem = { config = "powerpc-apple-darwin"; }; };
  llvm = pkgsCross.llvmPackages_16;

in pkgs.stdenv.mkDerivation {
  pname = "abzu-xnu-10.5.8";
  version = "1228";
  src = xnu-1058-src;

  # We will add our custom patches here later
  # patches = [ ./patches/10.5.8-hfs-root.patch ];

  buildInputs = [ llvm.clang llvm.lld ];

  buildPhase = ''
    make ARCH_CONFIGS=PPC KERNEL_CONFIGS=RELEASE \
         CC=${llvm.clang}/bin/clang \
         LD=${llvm.lld}/bin/ld.lld
  '';

  installPhase = ''
    mkdir -p $out
    cp BUILD/obj/RELEASE/PPC/mach_kernel $out/
  '';
}
