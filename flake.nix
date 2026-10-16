{
  description = "Abzu Custom XNU Kernel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      # 1. Explicitly declare the host system (GitHub Actions macos-14 is aarch64-darwin)
      system = "aarch64-darwin";
      
      # 2. Explicitly declare the cross-compilation target
      crossSystem = { config = "powerpc-apple-darwin"; };

      # 3. Import nixpkgs with BOTH systems explicitly defined
      pkgs = import nixpkgs {
        inherit system crossSystem;
      };
      
      llvm = pkgs.llvmPackages_16;

      xnu-src = pkgs.fetchurl {
        url = "https://opensource.apple.com/tarballs/xnu/xnu-1228.tar.gz";
        sha256 = "0000000000000000000000000000000000000000000000000000";
      };
    in
    {
      # 4. Use the explicit 'system' variable here too
      packages.${system}.abzu-xnu-10-5-8 = pkgs.stdenv.mkDerivation {
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
