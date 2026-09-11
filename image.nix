{ pkgs, src, userUid ? 1000, userGid ? 1000 }:

let
  # Known-good deterministic Alpine pin already used in nixpkgs tests.
  # The digest corresponds to Alpine 3.20.3. Refresh this pin with
  # nix-prefetch-docker when updating the control-plane base.
  alpineBase = pkgs.dockerTools.pullImage {
    imageName = "alpine";
    imageDigest = "sha256:beefdbd8a1da6d2915566fde36db9db0b524eb737fc57cd1367effd16dc0d06d";
    sha256 = "0gf7wbjp37zbni3pz8vdgq1mss6mz69wynms0gqhq7lsxfmg9xj9";
    finalImageName = "alpine";
    finalImageTag = "latest";
  };

  # The SSH control plane must keep working even when /env is broken and
  # even after the host /nix mount hides the image's own /nix directory.
  # Build these binaries statically, then copy their bytes into ordinary
  # rootfs paths rather than exposing their Nix store paths in the image.
  controlOpenSSH =
    (pkgs.pkgsStatic.openssh.override {
      etcDir = "/etc/ssh";
      isNixos = false;
      withLdns = false;
    }).overrideAttrs (old: {
      configureFlags = (old.configureFlags or [ ]) ++ [
        "--libexecdir=/usr/lib/ssh"
        "--with-privsep-path=/var/empty"
        "--with-privsep-user=sshd"
      ];
      # Keep the compiled runtime path outside /nix, but install the helpers
      # into the derivation so image assembly can copy them into /usr/lib/ssh.
      installFlags = (old.installFlags or [ ]) ++ [
        "libexecdir=$out/libexec"
      ];
    });

  controlSuExec = pkgs.pkgsStatic.su-exec;
in
pkgs.dockerTools.buildLayeredImage {
  name = "flake-docker";
  tag = "latest";
  fromImage = alpineBase;

  # No /nix/store closure is copied into the image. The runtime /nix tree is
  # supplied by the NixOS host with a read-only bind mount.
  includeStorePaths = false;
  contents = [ ];

  extraCommands = ''
    mkdir -p \
      bootstrap \
      env \
      workspace \
      home/pn \
      etc/nix \
      etc/ssh \
      etc/flake-docker \
      run/sshd \
      run/flake-docker \
      usr/local/bin \
      usr/sbin \
      usr/lib/ssh \
      sbin \
      var/empty

    install -m755 ${src}/entrypoint.sh entrypoint.sh
    install -m755 ${src}/dev usr/local/bin/dev
    install -m755 ${src}/ssh-session usr/local/bin/ssh-session
    install -m755 ${src}/start-sshd usr/local/bin/start-sshd
    install -m644 ${src}/sshd_config etc/ssh/sshd_config
    install -m644 ${src}/SKILL.md etc/flake-docker/SKILL.md
    install -m644 ${src}/bootstrap-flake.nix bootstrap/flake.nix

    install -m755 ${controlOpenSSH}/bin/sshd usr/sbin/sshd
    cp -a ${controlOpenSSH}/libexec/. usr/lib/ssh/
    install -m755 ${controlSuExec}/bin/su-exec sbin/su-exec

    cat > etc/nix/nix.conf <<'EOF'
    experimental-features = nix-command flakes
    EOF

    # The custom layer replaces Alpine's account database with the minimal
    # identities required by the container and OpenSSH privilege separation.
    cat > etc/passwd <<EOF
    root:x:0:0:root:/root:/bin/ash
    sshd:x:22:22:sshd:/var/empty:/bin/false
    pn:x:${toString userUid}:${toString userGid}:pn:/home/pn:/bin/ash
    EOF

    cat > etc/group <<EOF
    root:x:0:root
    sshd:x:22:sshd
    pn:x:${toString userGid}:pn
    EOF

    cat > etc/shadow <<'EOF'
    root:*:0:0:99999:7:::
    sshd:!:0:0:99999:7:::
    pn::0:0:99999:7:::
    EOF
  '';

  fakeRootCommands = ''
    chown ${toString userUid}:${toString userGid} env workspace home/pn
    chmod 0755 env workspace
    chmod 0700 home/pn
    chmod 0600 etc/shadow
    chown 0:0 var/empty
    chmod 0755 var/empty
  '';

  config = {
    Env = [
      "NIX_REMOTE=daemon"
      "HOME=/home/pn"
      "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    ];
    WorkingDir = "/workspace";
    ExposedPorts = {
      "2222/tcp" = { };
    };
    Entrypoint = [ "/entrypoint.sh" ];
  };
}
