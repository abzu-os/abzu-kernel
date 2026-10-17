{
  description = "Abzu Custom XNU Kernel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      llvm = pkgs.llvmPackages_18;
      clang = llvm.clang;
      lld = llvm.lld;

      xnu-src = pkgs.fetchFromGitHub {
        owner = "apple-oss-distributions";
        repo = "xnu";
        rev = "xnu-1228";
        hash = "sha256-77fddC7Udhh4uuqCJuoyeAuRCNJiNBpZZgivOM8p1gU=";
      };
    in
    {
      packages.${system}.abzu-xnu-10-5-8 = pkgs.stdenv.mkDerivation {
        pname = "abzu-xnu-10-5-8";
        version = "1228";
        src = xnu-src;

        nativeBuildInputs = [ pkgs.gnumake pkgs.gnused pkgs.gnugrep pkgs.findutils pkgs.python3 pkgs.coreutils pkgs.perl pkgs.tcsh clang lld ];
        hardeningDisable = [ "all" ];

        patchPhase = ''
          runHook prePatch
          echo "=== DEBUG: Exhaustively patching hardcoded paths using GNU sed ==="
          
          # 1. Strip DOS line endings first to ensure all subsequent regex matches work
          find . -type f -exec sed -i 's/\r//g' {} +
          
          # 2. Apply all our replacements
          find . -type f -exec sed -i \
            -e 's|/usr/sbin/sysctl|sysctl|g' \
            -e 's|/usr/bin/config|config|g' \
            -e 's|/usr/sbin/config|config|g' \
            -e 's|/bin/pwd|pwd|g' \
            -e 's|/bin/mkdir|mkdir|g' \
            -e 's|/bin/cp|cp|g' \
            -e 's|#!/bin/csh|#!'"${pkgs.tcsh}"'/bin/tcsh|g' \
            -e 's|/bin/csh|tcsh|g' \
            -e 's|/usr/bin/perl|'"${pkgs.perl}"'/bin/perl|g' \
            -e 's|/usr/local/bin/relpath|relpath|g' \
            -e 's|/usr/bin/tr|tr|g' \
            -e 's|/usr/bin/uname|uname|g' \
            -e 's|-mno-altivec||g' \
            -e 's|-mcpu=[^ ]*||g' \
            -e 's|-arch ppc||g' \
            -e 's|-mmultiple||g' \
            -e 's|-mno-multiple||g' \
            -e 's|-mmacosx-version-min=[^ ]*||g' \
            -e 's|-isysroot [^ ]*||g' \
            {} +
          
          echo "=== DEBUG: Verifying patches ==="
          grep -rn "/usr/bin/config" . && echo "ERROR: /usr/bin/config still hardcoded!" || echo "SUCCESS: /usr/bin/config patched"
          grep -rn "/usr/sbin/config" . && echo "ERROR: /usr/sbin/config still hardcoded!" || echo "SUCCESS: /usr/sbin/config patched"
          
          runHook postPatch
        '';

        buildPhase = ''
          runHook preBuild

          mkdir -p "$TMPDIR/bin"
          
          # Dummy config script to satisfy the XNU Makefile
          cat > "$TMPDIR/bin/config" << 'EOF'
#!/bin/sh
echo "Dummy config: skipping kernel configuration generation"
touch ioconf.c ioconf.h
EOF
          chmod +x "$TMPDIR/bin/config"

          # Dummy uname script to satisfy the XNU Makefile
          cat > "$TMPDIR/bin/uname" << 'EOF'
#!/bin/sh
if [ "$1" = "-s" ]; then
  echo "Darwin"
elif [ "$1" = "-r" ]; then
  echo "9.0.0"
else
  echo "Darwin"
fi
EOF
          chmod +x "$TMPDIR/bin/uname"

          # Mock relpath
          cat > "$TMPDIR/bin/relpath" << 'EOF'
#!/bin/sh
exec ${pkgs.python3}/bin/python3 -c "import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else '.'))" "$@"
EOF
          chmod +x "$TMPDIR/bin/relpath"

          # Mock sysctl to handle the -n flag and return plausible macOS values
          cat > "$TMPDIR/bin/sysctl" << 'EOF'
#!/bin/sh
PRINT_VALUE_ONLY=0
if [ "$1" = "-n" ]; then
  PRINT_VALUE_ONLY=1
  shift
fi
OID=$1
VALUE=""
case "$OID" in
  hw.logicalcpu) VALUE="4" ;;
  hw.physicalcpu) VALUE="4" ;;
  hw.memsize) VALUE="4294967296" ;;
  hw.ncpu) VALUE="4" ;;
  hw.activecpu) VALUE="4" ;;
  hw.cpufrequency) VALUE="2000000000" ;;
  hw.cachelinesize) VALUE="64" ;;
  hw.pagesize) VALUE="4096" ;;
  *) echo "sysctl: unknown oid '$OID'" >&2; exit 1 ;;
esac
if [ "$PRINT_VALUE_ONLY" -eq 1 ]; then
  echo "$VALUE"
else
  echo "$OID: $VALUE"
fi
EOF
          chmod +x "$TMPDIR/bin/sysctl"

          # CRITICAL: Force the Makefile to use our mocked tools via environment variables
          export CONFIG=config
          export UNAME=uname
          export PATH="$TMPDIR/bin:$PATH"

          echo "=== DEBUG: Checking PATH and tools ==="
          echo "PATH is: $PATH"
          command -v config || echo "WARNING: config not found in PATH!"
          command -v uname || echo "WARNING: uname not found in PATH!"
          command -v relpath || echo "WARNING: relpath not found in PATH!"
          command -v sysctl || echo "WARNING: sysctl not found in PATH!"
          command -v mkdir || echo "WARNING: mkdir not found in PATH!"
          command -v cp || echo "WARNING: cp not found in PATH!"
          command -v tcsh || echo "WARNING: tcsh not found in PATH!"
          command -v perl || echo "WARNING: perl not found in PATH!"
          command -v tr || echo "WARNING: tr not found in PATH!"

          export ARCH_CONFIGS=PPC KERNEL_CONFIGS=RELEASE
          export CC="${clang}/bin/clang -target powerpc-apple-darwin -m32"
          export LD="${lld}/bin/ld.lld"
          export SDKROOT=/

          make

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out

          make kernel

          echo "=== DEBUG: Listing main build output directory ==="
          ls -lh BUILD/obj/RELEASE_PPC/ || true

          if [ -f BUILD/obj/RELEASE_PPC/mach_kernel ]; then
            cp BUILD/obj/RELEASE_PPC/mach_kernel $out/mach_kernel
          elif [ -f BUILD/obj/PPC_RELEASE/mach_kernel ]; then
            cp BUILD/obj/PPC_RELEASE/mach_kernel $out/mach_kernel
          else
            echo "ERROR: mach_kernel was not produced by the build!"
            find BUILD/ -name 'mach_kernel*' || true
            exit 1
          fi

          echo "=== DEBUG: Final contents of \$out ==="
          ls -lh $out/

          runHook postInstall
        '';
      };
    };
}
