{ pkgs
, lib

# The NixOS configuration to be installed in the singularity container
, config

# Files and directories to place in the container in addition to the
# NixOS distribution. This is a list of attribute sets {source, target}
# where `source' is the file system object (regular file or directory)
# to be grafted in the file system at path `target'.
, contents ? []

, diskSize ? 1024

# Extra space to include in the container
, extraSpace ? 0

# Script that singularity will run when the container is opened.
, runScript

# Script to run as root user during the installation process.
, runAsRoot ? null
, postVM ? ""

, name ? "nixos-singularity-container"
}:

with lib;

let
  nixpkgs = lib.cleanSource pkgs.path;

  channelSources = pkgs.runCommand "nixos-${config.system.nixosVersion}" {} ''
    mkdir -p $out
    cp -prd ${nixpkgs} $out/nixos
    chmod -R u+w $out/nixos
    if [ ! -e $out/nixos/nixpkgs ]; then
      ln -s . $out/nixos/nixpkgs
    fi
    rm -rf $out/nixos/.git
    echo -n ${config.system.nixosVersionSuffix} > $out/nixos/.version-suffix
  '';

  metaClosure = pkgs.writeText "meta" ''
    ${config.system.build.toplevel}
    ${config.nix.package.out}
    ${channelSources}
  '';

  prepareImageInputs = with pkgs; [ e2fsprogs fakeroot lkl rsync config.system.build.nixos-prepare-root ] ++ stdenv.initialPath;

  shellScript = name: text:
    pkgs.writeScript name ''
      #!${pkgs.stdenv.shell}
      source /etc/bashrc
      set -e
      ${text}
    '';

  runAsRootFile = shellScript "run-as-root.sh" runAsRoot;
  runScriptFile = shellScript "run-script.sh" runScript;
  contentsWithScript = contents ++ [ { source = runScriptFile; target = "singularity"; } ];

  sources = map (x: x.source) contentsWithScript;
  targets = map (x: x.target) contentsWithScript;

  prepareImage = ''
    set -x
    export PATH=${pkgs.lib.makeSearchPathOutput "bin" "bin" prepareImageInputs}

    mkdir $out
    diskImage=nixos.raw
    truncate -s ${toString diskSize}M $diskImage

    mkfs.ext4 -F -L nixos $diskImage

    root="$PWD/root"
    mkdir -p $root

    set -f
    sources_=(${concatStringsSep " " sources})
    targets_=(${concatStringsSep " " targets})
    set +f

    for ((i = 0; i < ''${#targets_[@]}; i++)); do
      source="''${sources_[$i]}"
      target="''${targets_[$i]}"

      if [[ "$source" =~ '*' ]]; then
        # If the source name contains '*', perform globbing.
        mkdir -p $root/$target
        for fn in $source; do
          rsync -a --no-o --no-g "$fn" $root/$target/
        done
      else
        mkdir -p $root/$(dirname $target)
        if ! [ -e $root/$target ]; then
          rsync -a --no-o --no-g $source $root/$target
        else
          echo "duplicate entry $target -> $source"
          exit 1
        fi
      fi
    done

    fakeroot nixos-prepare-root $root ${channelSources} ${config.system.build.toplevel} closure

    cptofs -t ext4 -i $diskImage $root/* /
  '';
in pkgs.vmTools.runInLinuxVM (
  pkgs.runCommand "${name}.img"
    { inherit postVM;
      preVM = prepareImage;
      buildInputs = with pkgs; [ libfaketime utillinux e2fsprogs singularity ];
      exportReferencesGraph = [ "closure" metaClosure ];
      memSize = 1024;
    } ''
      rm -rf $out

      rootDisk=/dev/vda

      ln -s vda /dev/xvda
      ln -s vda /dev/sda

      mountPoint=/mnt
      mkdir $mountPoint
      mount $rootDisk $mountPoint

      mkdir -p /mnt/etc/nixos

      mount --rbind /dev $mountPoint/dev
      mount --rbind /proc $mountPoint/proc
      mount --rbind /sys $mountPoint/sys

      NIXOS_INSTALL_BOOTLOADER=1 chroot $mountPoint /nix/var/nix/profiles/system/bin/switch-to-configuration boot
      chroot $mountPoint /nix/var/nix/profiles/system/activate

      rm -f $mountPoint/etc/machine-id
      ln -s sh $mountPoint/bin/bash
      rm $mountPoint/etc/hosts

      umount -R $mountPoint

      faketime -f "1970-01-01 00:00:01" tune2fs -T now -c 0 -i 0 $rootDisk

      size=$(resize2fs -P $rootDisk | awk '{print $NF}')

      mount $rootDisk $mountPoint
      cd $mountPoint

      #export PATH=$PATH:${pkgs.e2fsprogs}/bin/
      singularity create -s $((1 + size * 4 / 1024 + ${toString extraSpace})) $out
      tar -c . | singularity import $out
    '')
