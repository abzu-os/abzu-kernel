{
  description = "Abzu Custom XNU Kernel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-darwin";
      
      # CRITICAL FIX: Use the exact Nixpkgs system string for 32-bit PowerPC macOS
      crossSystem = { config = "powerpc-darwin"; };

      pkgs = import nixpkgs {
        inherit system crossSystem;
        config.allowUnsupportedSystem = true;
      };
      
      clang = pkgs.clang;
      lld = pkgs.lld;

      xnu-src = pkgs.fetchurl {
        url = "https://opensource.apple.com/tarballs/xnu/xnu-1228.tar.gz";
        sha256 = "0000000000000000000000000000000000000000000000000000";
      };
    in
    {
      packages.${system}.abzu-xnu-10-5-8 = pkgs.stdenv.mkDerivation {
        pname = "abzu-xnu-10-5-8";
        version = "1228";
        src = xnu-src;

        nativeBuildInputs = [ pkgs.buildPackages.gnumake clang lld ];

        buildPhase = ''
          runHook preBuild
          make ARCH_CONFIGS=PPC KERNEL_CONFIGS=RELEASE \
               CC=${clang}/bin/clang \
               LD=${lld}/bin/ld.lld \
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
