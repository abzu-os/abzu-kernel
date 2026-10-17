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

        # Explicitly add perl, grep, and findutils to guarantee they are in PATH
        nativeBuildInputs = [ pkgs.gnumake clang lld pkgs.perl pkgs.gnugrep pkgs.findutils ];
        hardeningDisable = [ "all" ];

        patchPhase = ''
          runHook prePatch
          
          echo "=== DEBUG: Checking tools ==="
          which perl || echo "ERROR: perl not found!"
          perl --version | head -n 2
          
          echo "=== DEBUG: Before patching ==="
          grep -rn "/usr/local/bin/relpath" . || echo "relpath NOT found before (good?)"
          grep -rn "/usr/bin/config" . || echo "config NOT found before (good?)"
          
          echo "Patching hardcoded paths in ALL files..."
          find . -type f -exec perl -pi -e 's|/usr/local/bin/relpath|relpath|g' {} \;
          find . -type f -exec perl -pi -e 's|/usr/bin/config|config|g' {} \;
          
          echo "=== DEBUG: After patching ==="
          grep -rn "/usr/local/bin/relpath" . || echo "SUCCESS: relpath was patched!"
          grep -rn "/usr/bin/config" . || echo "SUCCESS: config was patched!"
          
          runHook postPatch
        '';

        buildPhase = ''
          runHook preBuild
          
          mkdir -p $TMPDIR/bin
          cat > $TMPDIR/bin/relpath << 'EOF'
#!/usr/bin/env perl
use File::Spec;
my $path = shift;
my $base = shift || ".";
print File::Spec->abs2rel($path, $base), "\n";
EOF
          chmod +x $TMPDIR/bin/relpath
          
          export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$TMPDIR/bin:$PATH"
          
          make ARCH_CONFIGS=PPC KERNEL_CONFIGS=RELEASE \
               CC="${clang}/bin/clang -target powerpc-apple-darwin -m32" \
               LD="${lld}/bin/ld.lld" \
               SDKROOT=/
          
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out
          
          echo "=== DEBUG installPhase: Finding kernel files ==="
          find BUILD/ -type f \( -name "*kernel*" -o -name "*mach*" \)
          
          find BUILD/ -type f \( -name "*kernel*" -o -name "*mach*" \) -exec cp {} $out/ \; || true
          
          echo "=== DEBUG installPhase: Final contents of \$out ==="
          ls -lh $out/
          
          if [ -z "$(ls -A $out)" ]; then
            echo "ERROR: No kernel files found in BUILD directory!"
            exit 1
          fi
          
          runHook postInstall
        '';
      };
    };
}
