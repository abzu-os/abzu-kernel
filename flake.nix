{
  description = "Abzu Custom XNU Kernel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-darwin";
      crossSystem = { config = "powerpc-apple-darwin"; };

      pkgs = import nixpkgs {
        inherit system crossSystem;
        # CRITICAL: Tell Nix to allow building for powerpc-darwin even if 
        # it's not on the official "fully tested" list for every package.
        config.allowUnsupportedSystem = true;
      };
      
      # pkgs.clang is the cross-compiler (runs on aarch64-darwin, targets powerpc-darwin)
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

        # gnumake runs on the build machine, clang/lld are the cross-tools
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
