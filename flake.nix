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
      clang = llvm.clang-unwrapped;
      lld = llvm.lld;

      xnu-src = pkgs.fetchurl {
        url = "https://opensource.apple.com/tarballs/xnu/xnu-1228.tar.gz";
        sha256 = "sha256-QsUS0OUrg0LE7PMf7CnGF5HXQQ6tCELh8JMXrid6yT8=";
      };
    in
    {
      packages.${system}.abzu-xnu-10-5-8 = pkgs.stdenv.mkDerivation {
        pname = "abzu-xnu-10-5-8";
        version = "1228";
        src = xnu-src;

        nativeBuildInputs = [ pkgs.gnumake clang lld ];
        hardeningDisable = [ "all" ];

        buildPhase = ''
          runHook preBuild
          
          # Manually force the raw Clang to target 32-bit PowerPC macOS
          make ARCH_CONFIGS=PPC KERNEL_CONFIGS=RELEASE \
               CC="${clang}/bin/clang -target powerpc-apple-darwin -m32" \
               LD="${lld}/bin/ld.lld" \
               SDKROOT=/
          
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out
          
          echo "=== DEBUG installPhase: Listing BUILD directory ==="
          ls -lR BUILD/
          
          echo "=== DEBUG installPhase: Finding kernel files ==="
          find BUILD/ -type f \( -name "*kernel*" -o -name "*mach*" \)
          
          # Try to copy whatever looks like a kernel
          find BUILD/ -type f \( -name "*kernel*" -o -name "*mach*" \) -exec cp {} $out/ \; || true
          
          echo "=== DEBUG installPhase: Final contents of \$out ==="
          ls -lh $out/
          
          # INTENTIONALLY FAIL if empty, so Nix prints the debug logs above!
          if [ -z "$(ls -A $out)" ]; then
            echo "ERROR: No kernel files found in BUILD directory!"
            exit 1
          fi
          
          runHook postInstall
        '';
      };
    };
}
