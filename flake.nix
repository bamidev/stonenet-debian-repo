{
  description = "Manage the Debian package repository for Stonenet";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      flake-utils,
      nixpkgs,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        latestVersion = "0.6.0";
        minimumSupportedVersion = "0.3.0";

        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;

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
        buildRepo = pkgs.writers.writeBashBin "build" (
          with pkgs;
          ''
            set -e

            function include_packages() {
              DAEMON_FILE=$(${findutils}/bin/find ../../stonenet/out/debian/$1 -name "stonenet_*.deb")
              ${reprepro}/bin/reprepro -A $1 includedeb stone "$DAEMON_FILE"
              DESKTOP_FILE=$(${findutils}/bin/find ../../stonenet/out/debian/$1 -name "stonenet-desktop_*.deb")
              ${reprepro}/bin/reprepro -A $1 includedeb stone "$DESKTOP_FILE"
            }

            # Cross compile all the packages
            # The stonenet repo is expected to exist next to this folder
            (
              cd ../stonenet
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
          ''
        );
        publishRepo = pkgs.writers.writeBashBin "publish" (
          with pkgs;
          ''
            set -e
            ${lib.getExe openssh} -p 12346 stonenet@stonenet.org "echo -e '${latestVersion}\n${minimumSupportedVersion}' > /var/www/get.stonenet.org/version.txt"
            ${lib.getExe rsync} --delete -r -e '${lib.getExe openssh} -p 12346' ./repo/* stonenet@stonent.org:/var/www/get.stonenet.org/debian
            ${lib.getExe openssh} stonenet@bootstrap1.stonenet.org "apt update && apt-upgrade" 
            ${lib.getExe openssh} stonenet@bootstrap2.stonenet.org "apt update && apt-upgrade"
          ''
        );
        fullProcess = pkgs.writers.writeBashBin "publish" ''
          set -e

          echo Building packages for all supported platforms...
          ${lib.getExe buildRepo}
          echo Publishing built packages...
          ${lib.getExe publishRepo}
        '';
      in
      {
        apps = {
          build = {
            name = "Build Stonenet";
            type = "app";
            program = lib.getExe buildRepo;
          };
          default = {
            name = "Build & Publish Stonenet";
            type = "app";
            program = lib.getExe fullProcess;
          };
          publish = {
            name = "Publish Stonenet";
            type = "app";
            program = lib.getExe publishRepo;
          };
        };
      }
    );
}
