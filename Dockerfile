FROM alpine

ARG USER_UID=1000
ARG USER_GID=1000

RUN apk add --no-cache openssh-server su-exec \
  && mkdir -m 0755 /nix \
  && mkdir -m 0755 /etc/nix \
  && echo 'experimental-features = nix-command flakes' > /etc/nix/nix.conf \
  && addgroup -g "$USER_GID" pn \
  && adduser -D -u "$USER_UID" -G pn pn \
  && passwd -d pn \
  && mkdir -p /bootstrap /env /workspace /home/pn /etc/flake-docker /run/sshd \
  && chown -R "$USER_UID:$USER_GID" /bootstrap /env /workspace /home/pn

COPY flake.nix /bootstrap/flake.nix
COPY entrypoint.sh /entrypoint.sh
COPY dev /usr/local/bin/dev
COPY ssh-session /usr/local/bin/ssh-session
COPY start-sshd /usr/local/bin/start-sshd
COPY sshd_config /etc/ssh/sshd_config
COPY SKILL.md /etc/flake-docker/SKILL.md

RUN chmod +x /entrypoint.sh /usr/local/bin/dev /usr/local/bin/ssh-session /usr/local/bin/start-sshd \
  && chmod 0644 /etc/ssh/sshd_config \
  && chown "$USER_UID:$USER_GID" /bootstrap/flake.nix

ENV NIX_REMOTE=daemon
ENV HOME=/home/pn
WORKDIR /workspace

EXPOSE 2222
ENTRYPOINT ["/entrypoint.sh"]
