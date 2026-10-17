{
  description = "Abzu Custom XNU Kernel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs { inherit system; };
      
      llvm = pkgs.llvmPackages_18;

      xnu-src = pkgs.fetchurl {
        url = "https://opensource.apple.com/tarballs/xnu/xnu-1228.tar.gz";
        # THE REAL HASH!
        sha256 = "sha256-QsUS0OUrg0LE7PMf7CnGF5HXQQ6tCELh8JMXrid6yT8=";
      };
    in
    {
      packages.${system}.abzu-xnu-10-5-8 = pkgs.stdenv.mkDerivation {
        pname = "abzu-xnu-10-5-8";
        version = "1228";
        src = xnu-src;

        nativeBuildInputs = [ pkgs.gnumake llvm.clang llvm.lld ];
        hardeningDisable = [ "all" ];

        buildPhase = ''
          runHook preBuild
          
          # Manually force Clang to target 32-bit PowerPC macOS
          make ARCH_CONFIGS=PPC KERNEL_CONFIGS=RELEASE \
               CC="${llvm.clang}/bin/clang -target powerpc-apple-darwin -m32" \
               LD="${llvm.lld}/bin/ld.lld" \
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
