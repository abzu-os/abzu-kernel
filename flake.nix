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

      # NetBSD sources for usr.bin/config, fetched from the official
      # cvsweb.cgi raw endpoints (same files as generate-config.yml uses).
      nbConfigFile = name: pkgs.fetchurl {
        url = "https://cvsweb.netbsd.org/bsdweb.cgi/usr.bin/config/${name}?only-with-content-type=text%2Fplain&content-type=text%2Fplain&rev=HEAD;";
        inherit name;
        # NOTE: placeholder hashes — regenerate all with:
        #   nix-prefetch-url 'https://cvsweb.netbsd.org/bsdweb.cgi/usr.bin/config/<file>?...&rev=HEAD;'
        hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };

      # Authentic NetBSD `config` tool, compiled natively in the sandbox.
      # Provides the kernel configuration generator that XNU's build
      # invokes as bare `config` (after patchPhase strips /usr/bin prefix).
      netbsd-config = pkgs.stdenvNoCC.mkDerivation rec {
        pname = "netbsd-config";
        version = "9.0";

        srcFiles = map nbConfigFile [
          "main.c" "defs.h" "gram.y" "scan.l" "util.c" "sem.h" "sem.c"
          "files.c" "hash.c" "lint.c" "pack.c" "mkheaders.c" "mkmakefile.c"
          "mkioconf.c" "mkswap.c" "mkdevsw.c" "crc.c"
        ];

        nativeBuildInputs = [ pkgs.bison pkgs.flex pkgs.gawk ];

        unpackPhase = ''
          mkdir -p netbsd-config/sys
          cd netbsd-config
          for f in ${toString srcFiles}; do
            cp "$f" "$(basename "$f")"
            chmod +w "$(basename "$f")"
          done
        '';

        patchPhase = ''
          # main.c calls check_version(); provide it (defined below in gram.y)
          substituteInPlace main.c --replace 'check_version();' '// check_version();' || true
          # Inject a stub check_version definition into gram.y prologue
          awk '/^%[{]/ { print; $0 = "static void check_version(void) {}" } { print }' gram.y > gram.tmp
          mv gram.tmp gram.y
        '';

        buildPhase = ''
          flex -o scan.c scan.l
          bison -d -o gram.c gram.y
          gcc -I. -D_GNU_SOURCE -DMAKE_BOOTSTRAP \
            -D'__RCSID(x)=' -D'__COPYRIGHT(x)=' -D'__unused=' \
            -D'__printflike(x,y)=' \
            -o config main.c mkheaders.c mkmakefile.c mkioconf.c \
               gram.c scan.c util.c sem.c files.c hash.c lint.c \
               mkswap.c pack.c mkdevsw.c crc.c
        '';

        installPhase = ''
          mkdir -p $out/bin
          cp config $out/bin/config
        '';
      };
    in
    {
      packages.${system}.abzu-xnu-10-5-8 = pkgs.stdenv.mkDerivation {
        pname = "abzu-xnu-10-5-8";
        version = "1228";
        src = xnu-src;

        nativeBuildInputs = [ pkgs.gnumake pkgs.gnused pkgs.gnugrep pkgs.findutils pkgs.python3 pkgs.coreutils pkgs.perl pkgs.tcsh clang lld netbsd-config ];
        hardeningDisable = [ "all" ];

        patchPhase = ''
          runHook prePatch
          echo "=== DEBUG: Patching hardcoded paths ==="
          
          # 1. Make files writable to ensure patching succeeds in the sandbox
          find . -type f -exec chmod +w {} \;
          
          # 2. Strip DOS line endings from text files only (binary-safe:
          #    the old blanket rewrite corrupted git packfiles and other
          #    binaries in the tree).
          find . -type f \
            \( -name "*.c" -o -name "*.h" -o -name "*.S" -o -name "*.s" \
               -o -name "*.pl" -o -name "*.pm" -o -name "*.py" -o -name "*.sh" \
               -o -name "*.csh" -o -name "Makefile*" -o -name "*.defs" \
               -o -name "*.awk" -o -name "*.sed" -o -name "*.mk" -o -name "*.cmd" \) \
            -exec perl -pi -e 's/\r//g' {} \;
          
          # 3. Apply robust replacements for paths and unsupported compiler
          #    flags -- restricted to text/build files so binaries (firmware
          #    blobs, test fixtures) are never rewritten.
          find . -type f \
            \( -name "*.c" -o -name "*.h" -o -name "*.S" -o -name "*.s" \
               -o -name "*.pl" -o -name "*.pm" -o -name "*.py" -o -name "*.sh" \
               -o -name "*.csh" -o -name "Makefile*" -o -name "*.defs" \
               -o -name "*.awk" -o -name "*.sed" -o -name "*.mk" -o -name "*.cmd" \) \
            -exec perl -pi -e \
            's|/usr/local/bin/relpath|relpath|g;
             s|/usr/bin/config|config|g;
             s|/usr/sbin/config|config|g;
             s|/usr/bin/uname|uname|g;
             s|/usr/sbin/sysctl|sysctl|g;
             s|/usr/sbin//sysctl|sysctl|g;
             s|/usr/bin/tr|tr|g;
             s|/bin/pwd|pwd|g;
             s|/bin/mkdir|mkdir|g;
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

          # Make the authentic NetBSD config tool available as bare `config`
          # (patchPhase stripped /usr/bin/ prefixes; stdenv puts
          # netbsd-config/bin on PATH via nativeBuildInputs, but the XNU
          # makefiles invoke it relative to the source dir in some paths —
          # mirror it into our mock-bin for belt-and-braces).
          ln -sf ${netbsd-config}/bin/config "$TMPDIR/bin/config"

          export ARCH_CONFIGS=PPC KERNEL_CONFIGS=RELEASE
          export CC="${clang}/bin/clang -target powerpc-apple-darwin -m32"
          export LD="${lld}/bin/ld.lld"
          # NOTE: SDKROOT intentionally not exported. There is no Darwin SDK
          # in this sandbox; setting SDKROOT=/ made clang treat / as a sysroot
          # and silently resolve host headers under a wrong prefix, producing
          # miscompiled objects. XNU's own headers are supplied via -I flags
          # from its makefiles.

          # Explicitly build the kernel
          make build || make all || make

          echo "=== DEBUG: What did make actually build? ==="
          find BUILD/ -type f \( -name "*kernel*" -o -name "*mach*" -o -size +1M \) || true
          ls -lh BUILD/obj/RELEASE_PPC/ || true

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out

          echo "=== DEBUG: Searching for the compiled kernel ==="
          find BUILD/ -type f \( -name "*kernel*" -o -name "*mach*" \)
          find BUILD/ -type f -size +1M
          
          # Copy the kernel if present. NOTE: the old "largest file"
          # fallback was removed -- it could silently package a random
          # large non-kernel file as $out/mach_kernel (silent corruption).
          # A build that did not produce mach_kernel must fail loudly.
          if [ -f BUILD/obj/RELEASE_PPC/mach_kernel ]; then
            cp BUILD/obj/RELEASE_PPC/mach_kernel $out/mach_kernel
          elif [ -f BUILD/obj/PPC_RELEASE/mach_kernel ]; then
            cp BUILD/obj/PPC_RELEASE/mach_kernel $out/mach_kernel
          else
            echo "ERROR: mach_kernel was not produced by the build!"
            find BUILD/ -name '*kernel*' || true
            find BUILD/ -name '*mach*' || true
            exit 1
          fi

          # Sanity check: the result must actually be an ELF/Mach-O object,
          # not an arbitrary file.
          head -c4 $out/mach_kernel | od -An -tx1 | grep -qE '7f 45 4c 46|cf fa ed fe|fe ed fa cf|4d 61 63 68|de c0 17 0b|0b 17 c0 de' \
            || { echo "ERROR: $out/mach_kernel is not a recognizable kernel binary"; exit 1; }

          echo "=== DEBUG: Final contents of \$out ==="
          ls -lh $out/

          runHook postInstall
        '';
      };
    };
}
