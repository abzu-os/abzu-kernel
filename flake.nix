{
  description = "Abzu Custom XNU Kernel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      # We are building ON Linux (x86_64-linux)
      system = "x86_64-linux";
      
      # NOTE: powerpc-darwin is NOT a supported crossSystem in nixpkgs'
      # stdenv/gcc wrapper (it rejects unknown "-darwin" triples with
      # "Unknown architecture"), and XNU 1228 (Mac OS X 10.5.8) predates
      # any Mach-O PowerPC support in LLD -- linking would fail even if
      # the evaluation succeeded. Build therefore with *native* Linux
      # tools and drive clang directly with its built-in powerpc
      # backend; no cross-installed toolchain is needed.

      # Import nixpkgs for the host system only
      pkgs = import nixpkgs { inherit system; };

      # Use the LLVM tools from the native package set
      llvm = pkgs.llvmPackages_18;
      clang = llvm.clang;   # wrapper provides the resource dir / sysroot flags
      lld = llvm.lld;

      # The original opensource.apple.com tarballs were taken offline by
      # Apple, so pull the same release from the official
      # apple-oss-distributions GitHub mirror. Verified: this tag's
      # archive hashes to exactly the same sha256 as Apple's old
      # xnu-1228.tar.gz (the botched "xnu-1228.11.18" ref never existed;
      # 10.5.8 actually corresponds to xnu-1228.15.4). fetchFromGitHub
      # (not fetchurl) is required here: github.com archive URLs
      # redirect to codeload.github.com, which Nix refuses to download
      # with plain fetchurl because it cannot be authenticated.
        xnu-src = pkgs.fetchFromGitHub {
        owner = "apple-oss-distributions";
        repo = "xnu";
        rev = "xnu-1228";
        hash = "sha256-QsUS0OUrg0LE7PMf7CnGF5HXQQ6tCELh8JMXrid6yT8="; # <--- THIS IS THE OLD ONE
      };
    in
    {
      packages.${system}.abzu-xnu-10-5-8 = pkgs.stdenv.mkDerivation {
        pname = "abzu-xnu-10-5-8";
        version = "1228";
        src = xnu-src;
        # fetchFromGitHub unpacks the tag archive into "xnu-xnu-1228",
        # not the "xnu-1228" directory Apple's old tarball used, so pin it.
        sourceRoot = "xnu-xnu-1228";

        # Native build inputs run on the Linux host
        nativeBuildInputs = [ pkgs.gnumake pkgs.gnused pkgs.gnugrep pkgs.findutils pkgs.python3 clang lld ];
        hardeningDisable = [ "all" ];

        patchPhase = ''
          runHook prePatch
          echo "=== DEBUG: Patching hardcoded paths using GNU sed ==="
          
          find . -type f -exec sed -i 's|/usr/local/bin/relpath|relpath|g' {} +
          find . -type f -exec sed -i 's|/usr/bin/config|config|g' {} +
          find . -type f -exec sed -i 's|/usr/sbin/config|config|g' {} +
          
          echo "=== DEBUG: Verifying patches ==="
          grep -rn "/usr/local/bin/relpath" . && echo "ERROR: relpath still hardcoded!" || echo "SUCCESS: relpath patched"
          grep -rn "/usr/bin/config" . && echo "ERROR: /usr/bin/config still hardcoded!" || echo "SUCCESS: /usr/bin/config patched"
          grep -rn "/usr/sbin/config" . && echo "ERROR: /usr/sbin/config still hardcoded!" || echo "SUCCESS: /usr/sbin/config patched"
          
          runHook postPatch
        '';

        buildPhase = ''
          runHook preBuild

          mkdir -p "$TMPDIR/bin"
          # XNU's own relpath tool is a *shell* script (osfmk and the
          # libkern misc scripts call it as `relpath file base`), so
          # provide a POSIX-sh drop-in replacement using python3 (which
          # is in nativeBuildInputs) for exact os.path.relpath semantics.
          # NOTE: this script is generated with echo instead of a heredoc
          # because the Nix indented-string syntax rejects dollar-brace
          # sequences here (they would be parsed as interpolations).
          {
            echo '#!/bin/sh'
            echo '# relpath target base -- print target path relative to base'
            echo 'exec ${pkgs.python3}/bin/python3 -c "'
            echo 'import os, sys'
            echo "print(os.path.relpath(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else '.'))"
            echo '" "$@"'
          } > "$TMPDIR/bin/relpath"
          chmod +x "$TMPDIR/bin/relpath"

          # NOTE: do NOT prepend /usr/sbin:/usr/bin:/bin:/sbin to PATH
          # here. Nix sandboxes have no /usr/sbin/config (that was an
          # Ubuntu-host assumption); the patchPhase rewrites XNU's
          # hardcoded config paths to a bare `config`, which must resolve
          # from the sandbox PATH, and hardcoding host directories only
          # shadows stdenv tools.
          export PATH="$TMPDIR/bin:$PATH"

          echo "=== DEBUG: Checking PATH and tools ==="
          echo "PATH is: $PATH"
          command -v config || echo "WARNING: config not found in PATH!"
          command -v relpath || echo "WARNING: relpath not found in PATH!"

          # ARCH_CONFIGS/KERNEL_CONFIGS are passed via the environment
          # instead of the command line: make command-line overrides
          # CANNOT be reassigned inside XNU's Makefile, and its PPC
          # branch does exactly that (`ARCH_CONFIGS=i386` for the
          # libkdyld helper) -- with a CLI override GNU make aborts with
          # "Cannot overwrite variable ARCH_CONFIGS because it is read
          # only". Environment assignment has the same effect for the
          # build but stays overridable.
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

          # XNU 1228's top-level make target "all" only builds the
          # supporting tools; it never links mach_kernel. The kernel
          # binary itself is produced by the separate "kernel" target,
          # which must be run explicitly here (it is incremental, so
          # already-compiled objects are reused). ARCH_CONFIGS, CC, LD
          # and SDKROOT are still exported from buildPhase -- keep them
          # out of the command line for the read-only-variable reason
          # noted there.
          make kernel

          echo "=== DEBUG: Listing main build output directory ==="
          ls -lh BUILD/obj/RELEASE_PPC/ || true

          # Install the actual kernel binary deterministically; a
          # name-based copy beats guessing by file size.
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
