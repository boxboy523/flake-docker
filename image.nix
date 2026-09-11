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

  # Build OpenSSH statically, but stage it as an FHS subtree inside the
  # derivation. The binaries therefore contain /usr/... runtime paths rather
  # than /nix/store/... paths. image.nix later copies that subtree into the
  # Alpine rootfs, so SSH remains independent from the runtime /nix mount.
  controlOpenSSH =
    (pkgs.pkgsStatic.openssh.override {
      isNixos = false;
      withLdns = false;
    }).overrideAttrs (old: {
      # The staging derivation is not a normal reusable OpenSSH package. It is
      # only an FHS root fragment consumed by image.nix, so split dev/man
      # outputs would be meaningless and must not be required by Nix.
      outputs = [ "out" ];
      dontAddPrefix = true;

      configureFlags =
        builtins.filter
          (flag:
            !(pkgs.lib.hasPrefix "--sbindir=" flag)
            && !(pkgs.lib.hasPrefix "--sysconfdir=" flag)
            && !(pkgs.lib.hasPrefix "--libexecdir=" flag))
          (old.configureFlags or [ ])
        ++ [
          "--prefix=/usr"
          "--sbindir=/usr/sbin"
          "--sysconfdir=/etc/ssh"
          "--libexecdir=/usr/lib/ssh"
          "--with-privsep-path=/var/empty"
          "--with-privsep-user=sshd"
        ];

      installPhase = ''
        runHook preInstall
        make install-nokeys DESTDIR="$out"
        runHook postInstall
      '';

      # The upstream nixpkgs post-install/checks assume a normal Nix package
      # layout such as $out/bin. This derivation deliberately stages an FHS
      # root instead, so image assembly is the relevant consumer/test.
      postInstall = "";
      doInstallCheck = false;
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

    install -m755 ${controlOpenSSH}/usr/sbin/sshd usr/sbin/sshd
    cp -a ${controlOpenSSH}/usr/lib/ssh/. usr/lib/ssh/
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
