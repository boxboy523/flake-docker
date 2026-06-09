FROM alpine

RUN mkdir -m 0755 /nix \
  && mkdir -m 0755 /etc/nix \
  && echo 'sandbox = false' > /etc/nix/nix.conf \
  && echo 'trusted-users = root pn' >> /etc/nix/nix.conf \
  && echo 'experimental-features = nix-command flakes' >> /etc/nix/nix.conf \
  && adduser -D -u 1000 pn \
  && mkdir -p /env && chown 1000:1000 /env

COPY --chown=1000:1000 flake.nix /env/flake.nix
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV NIX_REMOTE=daemon

ENTRYPOINT ["/entrypoint.sh"]

USER 1000
