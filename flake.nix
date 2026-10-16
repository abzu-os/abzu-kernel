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
      
      # CRITICAL FIX: Use buildPackages to get the HOST's LLVM (aarch64-darwin)
      # This is the compiler that will run on the GitHub runner and output PPC code.
      llvm = pkgs.buildPackages.llvmPackages_18;

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

        # nativeBuildInputs run on the build machine. 
        # We explicitly pull gnumake from buildPackages as well.
        nativeBuildInputs = [ pkgs.buildPackages.gnumake llvm.clang llvm.lld ];

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
