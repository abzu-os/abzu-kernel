{
  description = "Abzu Custom XNU Kernel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      pkgsCross = import nixpkgs {
        crossSystem = {
          config = "powerpc-apple-darwin";
        };
      };
      
      llvm = pkgsCross.llvmPackages_16;

      xnu-src = pkgsCross.fetchurl {
        url = "https://opensource.apple.com/tarballs/xnu/xnu-1228.tar.gz";
        sha256 = "0000000000000000000000000000000000000000000000000000";
      };
    in
    {
      # Changed from 'default' to 'abzu-xnu-10-5-8' to match our build command
      packages.aarch64-darwin.abzu-xnu-10-5-8 = pkgsCross.stdenv.mkDerivation {
        pname = "abzu-xnu-10-5-8";
        version = "1228";
        src = xnu-src;

        buildInputs = [ llvm.clang llvm.lld ];

        buildPhase = ''
          runHook preBuild
          make ARCH_CONFIGS=PPC KERNEL_CONFIGS=RELEASE \
               CC=${llvm.clang}/bin/clang \
               LD=${llvm.lld}/bin/ld.lld \
               SDKROOT=/
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out
          find BUILD -name "mach_kernel" -exec cp {} $out/ \; || true
          runHook postInstall
        '';
      };
    };
}
