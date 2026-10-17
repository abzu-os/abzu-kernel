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

        # Removed procps since we are mocking sysctl
        nativeBuildInputs = [ pkgs.gnumake pkgs.gnused pkgs.gnugrep pkgs.findutils pkgs.python3 pkgs.coreutils clang lld ];
        hardeningDisable = [ "all" ];

        patchPhase = ''
          runHook prePatch
          echo "=== DEBUG: Exhaustively patching hardcoded paths using GNU sed ==="
          
          find . -type f -exec sed -i \
            -e 's|/usr/sbin/sysctl|sysctl|g' \
            -e 's|/usr/sbin//sysctl|sysctl|g' \
            -e 's|/usr/bin/config|config|g' \
            -e 's|/usr/sbin/config|config|g' \
            -e 's|/usr/sbin//config|config|g' \
            -e 's|/bin/pwd|pwd|g' \
            -e 's|/bin//pwd|pwd|g' \
            -e 's|/bin/mkdir|mkdir|g' \
            -e 's|/bin//mkdir|mkdir|g' \
            -e 's|/usr/local/bin/relpath|relpath|g' \
            {} +
          
          echo "=== DEBUG: Verifying patches ==="
          grep -rn "/usr/sbin/sysctl" . && echo "ERROR: sysctl still hardcoded!" || echo "SUCCESS: sysctl patched"
          grep -rn "/usr/bin/config" . && echo "ERROR: config still hardcoded!" || echo "SUCCESS: config patched"
          grep -rn "/bin/pwd" . && echo "ERROR: pwd still hardcoded!" || echo "SUCCESS: pwd patched"
          grep -rn "/bin/mkdir" . && echo "ERROR: mkdir still hardcoded!" || echo "SUCCESS: mkdir patched"
          grep -rn "/usr/local/bin/relpath" . && echo "ERROR: relpath still hardcoded!" || echo "SUCCESS: relpath patched"
          
          runHook postPatch
        '';

        buildPhase = ''
          runHook preBuild

          mkdir -p "$TMPDIR/bin"
          
          # Mock relpath
          {
            echo '#!/bin/sh'
            echo 'exec ${pkgs.python3}/bin/python3 -c "'
            echo 'import os, sys'
            echo "print(os.path.relpath(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else '.'))"
            echo '" "$@"'
          } > "$TMPDIR/bin/relpath"
          chmod +x "$TMPDIR/bin/relpath"

          # Mock sysctl to return plausible macOS values for the build system
          {
            echo '#!/bin/sh'
            echo 'case "$1" in'
            echo '  hw.logicalcpu) echo "hw.logicalcpu: 4" ;;'
            echo '  hw.physicalcpu) echo "hw.physicalcpu: 4" ;;'
            echo '  hw.memsize) echo "hw.memsize: 4294967296" ;;'
            echo '  hw.ncpu) echo "hw.ncpu: 4" ;;'
            echo '  hw.activecpu) echo "hw.activecpu: 4" ;;'
            echo '  hw.cpufrequency) echo "hw.cpufrequency: 2000000000" ;;'
            echo '  hw.cachelinesize) echo "hw.cachelinesize: 64" ;;'
            echo '  hw.pagesize) echo "hw.pagesize: 4096" ;;'
            echo '  *) echo "sysctl: unknown oid ''$1" >&2; exit 1 ;;'
            echo 'esac'
          } > "$TMPDIR/bin/sysctl"
          chmod +x "$TMPDIR/bin/sysctl"

          export PATH="$TMPDIR/bin:$PATH"

          echo "=== DEBUG: Checking PATH and tools ==="
          echo "PATH is: $PATH"
          command -v config || echo "WARNING: config not found in PATH!"
          command -v relpath || echo "WARNING: relpath not found in PATH!"
          command -v pwd || echo "WARNING: pwd not found in PATH!"
          command -v sysctl || echo "WARNING: sysctl not found in PATH!"
          command -v mkdir || echo "WARNING: mkdir not found in PATH!"

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
