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
        hash = "sha256-QsUS0OUrg0LE7PMf7CnGF5HXQQ6tCELh8JMXrid6yT8=";
      };
    in
    {
      packages.${system}.abzu-xnu-10-5-8 = pkgs.stdenv.mkDerivation {
        pname = "abzu-xnu-10-5-8";
        version = "1228";
        src = xnu-src;
        sourceRoot = "xnu-xnu-1228";

        nativeBuildInputs = [ pkgs.gnumake pkgs.gnused pkgs.gnugrep pkgs.findutils pkgs.python3 pkgs.coreutils pkgs.perl pkgs.tcsh clang lld ];
        hardeningDisable = [ "all" ];

        patchPhase = ''
          runHook prePatch
          echo "=== DEBUG: Patching hardcoded paths ==="
          
          # 1. Make files writable to ensure patching succeeds in the sandbox
          find . -type f -exec chmod +w {} \;
          
          # 2. Strip DOS line endings to ensure regex matches work
          find . -type f -exec perl -pi -e 's/\r//g' {} \;
          
          # 3. Apply robust replacements for paths and unsupported compiler flags
          find . -type f -exec perl -pi -e \
            's|/usr/local/bin/relpath|relpath|g;
             s|/usr/bin/config|config|g;
             s|/usr/sbin/config|config|g;
             s|/usr/bin/uname|uname|g;
             s|/usr/sbin/sysctl|sysctl|g;
             s|/usr/bin/tr|tr|g;
             s|-mno-altivec||g;
             s|-mcpu=[^ ]*||g;
             s|-arch ppc||g;
             s|-mmultiple||g;
             s|-mno-multiple||g;
             s|-mmacosx-version-min=[^ ]*||g;
             s|-isysroot [^ ]*||g' {} \;
          
          runHook postPatch
        '';

        buildPhase = ''
          runHook preBuild

          mkdir -p "$TMPDIR/bin"
          
          # Mock relpath
          cat > "$TMPDIR/bin/relpath" << 'EOF'
#!/bin/sh
exec ${pkgs.python3}/bin/python3 -c "import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else '.'))" "$@"
EOF
          chmod +x "$TMPDIR/bin/relpath"

          # Mock uname
          cat > "$TMPDIR/bin/uname" << 'EOF'
#!/bin/sh
if [ "$1" = "-s" ]; then echo "Darwin"
elif [ "$1" = "-r" ]; then echo "9.0.0"
elif [ "$1" = "-m" ]; then echo "Power Macintosh"
elif [ "$1" = "-p" ]; then echo "powerpc"
else echo "Darwin"; fi
EOF
          chmod +x "$TMPDIR/bin/uname"

          # Mock sysctl
          cat > "$TMPDIR/bin/sysctl" << 'EOF'
#!/bin/sh
if [ "$1" = "-n" ]; then shift; fi
case "$1" in
  hw.logicalcpu) echo "4" ;;
  hw.physicalcpu) echo "4" ;;
  hw.memsize) echo "4294967296" ;;
  hw.ncpu) echo "4" ;;
  hw.activecpu) echo "4" ;;
  hw.cpufrequency) echo "2000000000" ;;
  hw.cachelinesize) echo "64" ;;
  hw.pagesize) echo "4096" ;;
  *) echo "sysctl: unknown oid '$1'" >&2; exit 1 ;;
esac
EOF
          chmod +x "$TMPDIR/bin/sysctl"

          export PATH="$TMPDIR/bin:$PATH"

          export ARCH_CONFIGS=PPC KERNEL_CONFIGS=RELEASE
          export CC="${clang}/bin/clang -target powerpc-apple-darwin -m32"
          export LD="${lld}/bin/ld.lld"
          export SDKROOT=/

          # The default 'make' target builds the kernel
          make

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out

          # FIX: Removed 'make kernel'. The top-level Makefile has no 'kernel' target.
          # The kernel is already built by the 'make' command in the buildPhase.

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
