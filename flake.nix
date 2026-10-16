{
  description = "Abzu Custom XNU Kernel";

  inputs = {
    # Use the latest nixpkgs for the best cross-compilation support
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      # 1. Set up cross-compilation for PowerPC (32-bit)
      pkgsCross = import nixpkgs {
        crossSystem = {
          config = "powerpc-apple-darwin";
        };
      };
      
      llvm = pkgsCross.llvmPackages_16;

      # 2. Fetch the Apple open-source tarball for xnu-1228 (Mac OS X 10.5.8)
      xnu-src = pkgsCross.fetchurl {
        url = "https://opensource.apple.com/tarballs/xnu/xnu-1228.tar.gz";
        # We use a dummy hash of all zeros. Nix will intentionally fail 
        # and tell us the exact, correct hash to use here!
        sha256 = "0000000000000000000000000000000000000000000000000000";
      };
    in
    {
      # 3. Define the build package for the Apple Silicon (aarch64-darwin) runner
      packages.aarch64-darwin.default = pkgsCross.stdenv.mkDerivation {
        pname = "abzu-xnu-10.5.8";
        version = "1228";
        src = xnu-src;

        buildInputs = [ llvm.clang llvm.lld ];

        # XNU's build system is archaic. We pass our modern Nix tools to it.
        buildPhase = ''
          runHook preBuild
          make ARCH_CONFIGS=PPC KERNEL_CONFIGS=RELEASE \
               CC=${llvm.clang}/bin/clang \
               LD=${llvm.lld}/bin/ld.lld \
               SDKROOT=/
          runHook postBuild
        '';

        # Use 'find' to safely grab the mach_kernel regardless of exact subdirectory
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          find BUILD -name "mach_kernel" -exec cp {} $out/ \; || true
          runHook postInstall
        '';
      };
    };
}
