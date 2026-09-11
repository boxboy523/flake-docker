FROM alpine

ARG USER_UID=1000
ARG USER_GID=1000

RUN mkdir -m 0755 /nix \
  && mkdir -m 0755 /etc/nix \
  && echo 'experimental-features = nix-command flakes' > /etc/nix/nix.conf \
  && addgroup -g "$USER_GID" pn \
  && adduser -D -u "$USER_UID" -G pn pn \
  && mkdir -p /bootstrap /env /workspace /home/pn \
  && chown -R "$USER_UID:$USER_GID" /bootstrap /env /workspace /home/pn

COPY flake.nix /bootstrap/flake.nix
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
  && chown "$USER_UID:$USER_GID" /bootstrap/flake.nix

ENV NIX_REMOTE=daemon
ENV HOME=/home/pn
WORKDIR /workspace

USER ${USER_UID}:${USER_GID}
ENTRYPOINT ["/entrypoint.sh"]
