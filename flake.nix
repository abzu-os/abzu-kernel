{
  description = "Abzu Custom XNU Kernel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-darwin";
      crossSystem = { config = "powerpc-apple-darwin"; };

      pkgs = import nixpkgs {
        inherit system crossSystem;
      };
      
      # Updated to LLVM 18 (16 was removed from unstable)
      llvm = pkgs.llvmPackages_18;

      xnu-src = pkgs.fetchurl {
        url = "https://opensource.apple.com/tarballs/xnu/xnu-1228.tar.gz";
        sha256 = "0000000000000000000000000000000000000000000000000000";
      };
    in
    {
      packages.${system}.abzu-xnu-10-5-8 = pkgs.stdenv.mkDerivation {
        pname = "abzu-xnu-10-5-8";
        version = "1228";
        src = xnu-src;

        # Added gnumake explicitly for XNU's archaic build system
        nativeBuildInputs = [ pkgs.gnumake llvm.clang llvm.lld ];

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
