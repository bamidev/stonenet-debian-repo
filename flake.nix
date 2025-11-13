{
  description = "Manage the Debian package repository for reprepro";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, flake-utils, nixpkgs }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        distributionsFile = pkgs.writeText "distributions" ''
          Codename: stone
          Suite: stable oldstable
          Architectures: amd64 arm64 armhf
          Components: main
          SignWith: 8645E096A26140CB3C0FA1CBA4BAAFB95BC2C961
          Origin: Stonenet
          Label: Stonenet
          Description: A peer-to-peer & censorship-resistant social-media platform. 
        '';
        buildRepo = pkgs.writers.writeBashBin "build-repo" (with pkgs; ''
          set -e

          function include_packages() {
            DAEMON_FILE=$(${findutils}/bin/find ../../stonenet/package/out/$1 -name "stonenet_*.deb")
            ${reprepro}/bin/reprepro -A $1 includedeb stone "$DAEMON_FILE"
            DESKTOP_FILE=$(${findutils}/bin/find ../../stonenet/package/out/$1 -name "stonenet-desktop_*.deb")
            ${reprepro}/bin/reprepro -A $1 includedeb stone "$DESKTOP_FILE"
          }

          # Cross compile all the packages
          # The stonenet repo is expected to exist next to this folder
          (
            cd ../stonenet/package
            ./cross-build.sh
          )

          # Set up the repository, if it doesn't exist yet
          ${coreutils}/bin/mkdir -p repo/conf
          ${coreutils}/bin/cp ${distributionsFile} repo/conf/distributions
          ${coreutils}/bin/chmod 644 repo/conf/distributions

          # Create the repository, and include all the built packages into it
          (
            cd repo
            ${reprepro}/bin/reprepro createsymlinks
            ${reprepro}/bin/reprepro export

            include_packages amd64
            include_packages arm64
            include_packages armhf
          )
        '');
      in {
        apps.default = {
          name = "Build repository";
          type = "app";
          program = "${buildRepo}/bin/build-repo";
        };
      }
    );
}
