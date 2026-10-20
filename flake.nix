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

      # Pin the NetBSD source to an immutable commit so no placeholder
      # sha256 is needed.  builtins.fetchGit is pure when rev is given.
      netbsd-src = builtins.fetchGit {
        url = "https://github.com/NetBSD/src";
        rev = "b8c195433891dd19496fc95f8c5006239f0b5a7e";
      };

      netbsd-config = pkgs.stdenv.mkDerivation {
        pname = "netbsd-config";
        version = "9.0";
        src = netbsd-src;

        nativeBuildInputs = with pkgs; [
          bison
          flex
          gcc
          gnumake
        ];
        buildInputs = with pkgs; [
          libbsd
        ];

        unpackPhase = ''
          runHook preUnpack
          mkdir -p netbsd-config
          cp -r ${netbsd-src}/usr.bin/config/. netbsd-config/
          cp -r ${netbsd-src}/usr.bin/cksum/. netbsd-config/
          chmod -R u+w netbsd-config
          cd netbsd-config
          runHook postUnpack
        '';

        patchPhase = ''
          runHook prePatch

          # The NetBSD config tool uses several BSD-specific headers and
          # functions that do not exist on Linux/glibc.
          mkdir -p sys

          cat > sys/sysctl.h <<'EOF'
          #ifndef ABZU_SYS_SYSCTL_H
          #define ABZU_SYS_SYSCTL_H

          #include <stddef.h>

          static inline int
          sysctlbyname(const char *name, void *oldp, size_t *oldlenp,
                       void *newp, size_t newlen)
          {
              (void)name;
              (void)oldp;
              (void)newp;
              (void)newlen;
              if (oldlenp != NULL)
                  *oldlenp = 0;
              return 0;
          }

          #endif
          EOF

          cat > compat.h <<'EOF'
          #ifndef ABZU_COMPAT_H
          #define ABZU_COMPAT_H

          #include <stdint.h>
          #include <stddef.h>
          #include <stdio.h>
          #include <stdlib.h>
          #include <string.h>
          #include <stdarg.h>
          #include <unistd.h>
          #include <sys/types.h>

          #ifndef __RENAME
          # define __RENAME(x)
          #endif
          #ifndef __dead
          # define __dead
          #endif
          #ifndef __unused
          # define __unused __attribute__((__unused__))
          #endif
          #ifndef __printflike
          # define __printflike(fmtarg, firstvararg) \
              __attribute__((__format__(__printf__, fmtarg, firstvararg)))
          #endif
          #ifndef __arraycount
          # define __arraycount(a) (sizeof(a) / sizeof((a)[0]))
          #endif
          #ifndef __UNCONST
          # define __UNCONST(a) ((void *)(unsigned long)(const void *)(a))
          #endif
          #ifndef MIN
          # define MIN(a,b) ((a) < (b) ? (a) : (b))
          #endif
          #ifndef MAX
          # define MAX(a,b) ((a) > (b) ? (a) : (b))
          #endif

          #endif
          EOF

          cat > util.h <<'EOF'
          #ifndef ABZU_UTIL_H
          #define ABZU_UTIL_H
          #include "compat.h"
          #include <bsd/stdlib.h>
          #endif
          EOF

          # Redirect the NetBSD sources at the shims and libbsd headers.
          for f in *.c *.h *.y *.l; do
            [ -f "$f" ] || continue
            substituteInPlace "$f" \
              --replace '<vis.h>' '<bsd/vis.h>' \
              --replace '<util.h>' '"util.h"' \
              --replace '<sys/sysctl.h>' '"sys/sysctl.h"'
          done

          # config's main.c calls check_version(), which is defined later in
          # gram.y.  Since we are not using the full NetBSD build system we
          # simply drop the call; it only prints a version banner.
          perl -pi -e 's/\bcheck_version\s*\(\s*\)\s*;/\/\* check_version(); \*\//' main.c

          runHook postPatch
        '';

        buildPhase = ''
          runHook preBuild

          flex -o scan.c scan.l
          bison -d -o gram.c gram.y

          gcc -I. -I./sys -D_GNU_SOURCE -DMAKE_BOOTSTRAP \
            -D'__RCSID(x)=' -D'__COPYRIGHT(x)=' \
            -o config \
            main.c mkheaders.c mkmakefile.c mkioconf.c \
            gram.c scan.c util.c crc.c mkswap.c pack.c sem.c files.c \
            hash.c lint.c mkdevsw.c \
            -lfl -lbsd

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin
          cp config $out/bin/config
          runHook postInstall
        '';
      };
    in
    {
      packages.${system}.abzu-xnu-10-5-8 = pkgs.stdenv.mkDerivation {
        pname = "abzu-xnu-10-5-8";
        version = "1228";
        src = xnu-src;

        nativeBuildInputs = with pkgs; [
          gnumake
          gnused
          gnugrep
          findutils
          python3
          coreutils
          perl
          tcsh
          clang
          lld
          netbsd-config
        ];

        hardeningDisable = [ "all" ];

        patchPhase = ''
          runHook prePatch

          echo "=== DEBUG: Patching hardcoded paths ==="
          # 1. Make files writable so patching succeeds in the sandbox.
          find . -type f -exec chmod +w {} \;

          # 2. Strip DOS line endings from text files only (binary-safe).
          find . -type f \
            \( -name "*.c" -o -name "*.h" -o -name "*.S" -o -name "*.s" \
               -o -name "*.pl" -o -name "*.pm" -o -name "*.py" -o -name "*.sh" \
               -o -name "*.csh" -o -name "Makefile*" -o -name "*.defs" \
               -o -name "*.awk" -o -name "*.sed" -o -name "*.mk" -o -name "*.cmd" \) \
            -exec perl -pi -e 's/\r//g' {} \;

          # 3. Replace paths and unsupported compiler flags, restricted to
          # text/build files so binaries are never rewritten.
          find . -type f \
            \( -name "*.c" -o -name "*.h" -o -name "*.S" -o -name "*.s" \
               -o -name "*.pl" -o -name "*.pm" -o -name "*.py" -o -name "*.sh" \
               -o -name "*.csh" -o -name "Makefile*" -o -name "*.defs" \
               -o -name "*.awk" -o -name "*.sed" -o -name "*.mk" -o -name "*.cmd" \) \
            -exec perl -pi -e \
              's|/usr/local/bin/relpath|relpath|g; s|/usr/bin/config|config|g;
               s|/usr/sbin/config|config|g; s|/usr/bin/uname|uname|g;
               s|/usr/sbin/sysctl|sysctl|g; s|/usr/sbin//sysctl|sysctl|g;
               s|/usr/bin/tr|tr|g; s|/bin/pwd|pwd|g; s|/bin/mkdir|mkdir|g;
               s|-mno-altivec||g; s|-mcpu=[^ ]*||g; s|-arch ppc||g;
               s|-mmultiple||g; s|-mno-multiple||g;
               s|-mmacosx-version-min=[^ ]*||g; s|-isysroot [^ ]*||g' {} \;

          runHook postPatch
        '';

        buildPhase = ''
          runHook preBuild

          mkdir -p "$TMPDIR/bin"

          # Mock relpath
          cat > "$TMPDIR/bin/relpath" <<'EOF'
          #!/bin/sh
          exec ${pkgs.python3}/bin/python3 -c "import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else '.'))" "$@"
          EOF
          chmod +x "$TMPDIR/bin/relpath"

          # Mock uname
          cat > "$TMPDIR/bin/uname" <<'EOF'
          #!/bin/sh
          if [ "$1" = "-s" ]; then echo "Darwin"
          elif [ "$1" = "-r" ]; then echo "9.0.0"
          elif [ "$1" = "-m" ]; then echo "Power Macintosh"
          elif [ "$1" = "-p" ]; then echo "powerpc"
          else echo "Darwin"; fi
          EOF
          chmod +x "$TMPDIR/bin/uname"

          # Mock sysctl
          cat > "$TMPDIR/bin/sysctl" <<'EOF'
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

          # Expose the authentic NetBSD config tool as bare `config`.
          ln -sf ${netbsd-config}/bin/config "$TMPDIR/bin/config"

          export ARCH_CONFIGS=PPC
          export KERNEL_CONFIGS=RELEASE
          export CC="${clang}/bin/clang -target powerpc-apple-darwin -m32"
          export LD="${lld}/bin/ld.lld"

          build || make all || make

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

          # Sanity check: the result must actually be a Mach-O/ELF object.
          head -c4 $out/mach_kernel | od -An -tx1 | \
            grep -qE '7f 45 4c 46|cf fa ed fe|fe ed fa cf|4d 61 63 68|de c0 17 0b|0b 17 c0 de' \
            || { echo "ERROR: $out/mach_kernel is not a recognizable kernel binary"; exit 1; }

          runHook postInstall
        '';
      };
    };
}
