FROM registry.fedoraproject.org/fedora:43

LABEL maintainer="Rénich Bon Ćirić <renich@evalinux.com>"
LABEL description="Coreutilz: 100% GNU-compatible Coreutils in Zig 0.16.0"

# Install Coreutilz binaries into /usr/local/bin
COPY zig-out/bin/ /usr/local/bin/

# Default entrypoint: multicall binary
CMD ["/usr/local/bin/coreutilz", "--help"]
