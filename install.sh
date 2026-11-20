#!/bin/sh
set -eu

extension_id='mawaqit@akramb.com'
release_url="https://github.com/akramboussanni/mawaqit-bar/releases/latest/download/${extension_id}.shell-extension.zip"

if [ "$(id -u)" -eq 0 ]; then
    echo 'Run this as your normal GNOME user, without sudo.' >&2
    exit 1
fi
for command_name in curl gnome-extensions gsettings; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Required command missing: $command_name" >&2
        exit 1
    fi
done

install_tmp=$(mktemp -d)
trap 'rm -rf "$install_tmp"' EXIT
trap 'exit 1' HUP INT TERM

printf 'Downloading Mawaqit GNOME…\n'
curl --fail --show-error --location --retry 2 --connect-timeout 15 --max-time 120 \
    "$release_url" --output "$install_tmp/mawaqit.shell-extension.zip"
gnome-extensions install --force "$install_tmp/mawaqit.shell-extension.zip"

# A running Shell may not discover a newly installed UUID until the next login.
if ! gnome-extensions enable "$extension_id" 2>"$install_tmp/enable-error"; then
    enabled_list=$(gsettings get org.gnome.shell enabled-extensions)
    case "$enabled_list" in
        *"'$extension_id'"*) ;;
        '[]'|'@as []')
            gsettings set org.gnome.shell enabled-extensions "['$extension_id']"
            ;;
        \[*\])
            gsettings set org.gnome.shell enabled-extensions "${enabled_list%]}, '$extension_id']"
            ;;
        *)
            cat "$install_tmp/enable-error" >&2
            echo 'Could not read GNOME enabled extensions.' >&2
            exit 1
            ;;
    esac
fi
printf 'Installed and enabled Mawaqit GNOME. Log out and back in to load it.\n'
