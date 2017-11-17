{ config, lib, pkgs, ... }:

with lib;

let cfg = config.singularityContainer; in {
  imports = [ ];

  options = {
    singularityContainer = {
      diskSize = mkOption {
        type = types.int;
        default = 1024;
        description = ''
          The size of the singularity container in MiB while creating the container.
        '';
      };

      extraSpace = mkOption {
        type = types.int;
        default = 0;
        description = ''
          Extra space to leave in the container when it is shrunk to fit.
        '';
      };

      runAsRoot = mkOption {
        type = types.str;
        default = null;
        description = ''
          Script to run during container creation as root user.
        '';
      };

      runScript = mkOption {
        type = types.str;
        default = "#${stdenv.shell}\n exec /bin/bash";
        description = ''
          Script that singularity will run when invoking the container.
        '';
      };
    };
  };

  config = {
    system.build.singularityContainer = import ../../lib/make-singularity-container.nix {
      name = "nixos-singularity-${config.system.nixosLabel}-${pkgs.stdenv.system}";
      inherit pkgs lib config;
      diskSize = cfg.diskSize;
      extraSpace = cfg.extraSpace;
      runAsRoot = cfg.runAsRoot;
      runScript = cfg.runScript;
    };

    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      autoResize = true;
    };

    boot.isContainer = true;
  };
}
