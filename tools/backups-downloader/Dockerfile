FROM ubuntu:26.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        openssh-client \
        sshpass \
        unzip \
    && architecture="$(dpkg --print-architecture)" \
    && case "$architecture" in \
         amd64) aws_cli_architecture=x86_64 ;; \
         arm64) aws_cli_architecture=aarch64 ;; \
         *) echo "Unsupported AWS CLI architecture: $architecture" >&2; exit 1 ;; \
       esac \
    && curl --fail --show-error --silent \
         "https://awscli.amazonaws.com/awscli-exe-linux-${aws_cli_architecture}.zip" \
         --output /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip \
    && rm -rf /var/lib/apt/lists/*

COPY --chmod=755 download-backups.sh /app/download-backups.sh

ENTRYPOINT ["/app/download-backups.sh"]
