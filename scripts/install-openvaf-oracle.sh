#!/bin/sh
set -eu

openvaf_version="23.5.0"
archive_name="openvaf_23_5_0_linux_amd64.tar.gz"
archive_url="https://openva.fra1.cdn.digitaloceanspaces.com/${archive_name}"
archive_sha256="79c0e08ad948a7a9f460dc87be88b261bbd99b63a4038db3c64680189f44e4f0"
binary_sha256="6918195bc6cca54016095923bea190f7a1d96dd8b062104c602e8c28578cb5e3"
install_root="${OPENVAF_INSTALL_ROOT:-$HOME/.local/share/openvaf/${openvaf_version}/linux-amd64}"
shim_path="${OPENVAF_SHIM_PATH:-$HOME/.local/bin/openvaf}"
image_name="${OPENVAF_DOCKER_IMAGE:-swift-openvaf/openvaf-${openvaf_version}:ubuntu22}"
installation_evidence="${OPENVAF_INSTALLATION_EVIDENCE:-}"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

ensure_docker_running() {
    if docker info >/dev/null 2>&1; then
        return
    fi

    if command -v orb >/dev/null 2>&1; then
        orb start
    fi

    if ! docker info >/dev/null 2>&1; then
        echo "Docker is not running. Start Docker or OrbStack and retry." >&2
        exit 1
    fi
}

verify_sha256() {
    file_path="$1"
    expected="$2"
    actual="$(shasum -a 256 "$file_path" | awk '{ print $1 }')"
    if [ "$actual" != "$expected" ]; then
        echo "SHA-256 mismatch for $file_path" >&2
        echo "Expected: $expected" >&2
        echo "Actual:   $actual" >&2
        exit 1
    fi
}

require_command curl
require_command shasum
require_command tar
require_command docker

ensure_docker_running

mkdir -p "$install_root"
archive_path="$install_root/$archive_name"

if [ ! -f "$archive_path" ]; then
    curl -fL "$archive_url" -o "$archive_path"
fi

verify_sha256 "$archive_path" "$archive_sha256"
tar -xzf "$archive_path" -C "$install_root"
chmod 0755 "$install_root/openvaf"
verify_sha256 "$install_root/openvaf" "$binary_sha256"

docker build --platform linux/amd64 -t "$image_name" -f - "$install_root" <<'EOF'
FROM ubuntu:22.04
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates gcc binutils libc6-dev \
    && rm -rf /var/lib/apt/lists/*
COPY openvaf /usr/local/bin/openvaf
RUN chmod 0755 /usr/local/bin/openvaf
ENTRYPOINT ["/usr/local/bin/openvaf"]
EOF

mkdir -p "$(dirname "$shim_path")"
{
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' 'set -eu'
    printf '\n'
    printf 'image="%s"\n' "$image_name"
    printf '%s\n' 'workdir="$(pwd)"'
    printf '\n'
    printf '%s\n' 'exec docker run --rm --platform linux/amd64 \'
    printf '%s\n' '  --user "$(id -u):$(id -g)" \'
    printf '%s\n' '  -v "$workdir:/work" \'
    printf '%s\n' '  -w /work \'
    printf '%s\n' '  "$image" "$@"'
} > "$shim_path"
chmod 0755 "$shim_path"

reported_version="$("$shim_path" --version)"
printf '%s\n' "$reported_version"

if [ -n "$installation_evidence" ]; then
    evidence_directory="$(dirname "$installation_evidence")"
    mkdir -p "$evidence_directory"
    image_id="$(docker image inspect --format '{{.Id}}' "$image_name")"
    {
        printf '%s\n' '{'
        printf '  "archiveSHA256": "%s",\n' "$archive_sha256"
        printf '  "binarySHA256": "%s",\n' "$binary_sha256"
        printf '  "dockerImage": "%s",\n' "$image_name"
        printf '  "dockerImageID": "%s",\n' "$image_id"
        printf '  "openVAFVersion": "%s",\n' "$openvaf_version"
        printf '  "shimPath": "%s"\n' "$shim_path"
        printf '%s\n' '}'
    } > "$installation_evidence"
    printf '%s\n' "$reported_version" > "${installation_evidence%.json}-version.txt"
fi
