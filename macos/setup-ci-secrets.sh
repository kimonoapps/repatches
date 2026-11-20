#!/bin/sh
# Uploads the signing and notarization secrets the release workflow needs.
# Exports only the Developer ID Application identity, never other keychain keys.
set -eu

REPO="${REPO:-akramboussanni/mawaqit-bar}"
GH_TOKEN="${GH_TOKEN:-$(gh auth token --user akramboussanni 2>/dev/null || gh auth token)}"
export GH_TOKEN

line=$(security find-identity -v -p codesigning | grep '"Developer ID Application: ' | head -n 1)
if [ -z "$line" ]; then
    echo "No Developer ID Application identity found in your keychain." >&2
    exit 1
fi
fingerprint=$(printf '%s\n' "$line" | awk '{print $2}')
identity=$(printf '%s\n' "$line" | sed 's/.*"\(.*\)".*/\1/')
team_id=$(printf '%s\n' "$identity" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')
echo "Using $identity"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
P12_PASSWORD=$(openssl rand -hex 24)
export P12_PASSWORD

echo "macOS will ask to allow exporting keys from your keychain. Click Allow (or Always Allow)."
security export -t identities -f pkcs12 -P "$P12_PASSWORD" -o "$work/all.p12"
openssl pkcs12 -in "$work/all.p12" -passin env:P12_PASSWORD -nodes -out "$work/all.pem" 2>/dev/null
awk -v dir="$work" '
    /-----BEGIN CERTIFICATE-----/ { n++; out = dir "/cert" n ".pem" }
    /-----BEGIN (RSA |EC )?PRIVATE KEY-----/ { k++; out = dir "/key" k ".pem" }
    out { print > out }
    /-----END / { close(out); out = "" }
' "$work/all.pem"

cert=""
for candidate in "$work"/cert*.pem; do
    sha=$(openssl x509 -in "$candidate" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')
    [ "$sha" = "$fingerprint" ] && cert="$candidate" && break
done
public=$(openssl x509 -in "$cert" -noout -pubkey)
key=""
for candidate in "$work"/key*.pem; do
    [ "$(openssl pkey -in "$candidate" -pubout 2>/dev/null)" = "$public" ] && key="$candidate" && break
done
if [ -z "$cert" ] || [ -z "$key" ]; then
    echo "Could not find the Developer ID certificate and its private key in the export." >&2
    exit 1
fi
openssl pkcs12 -export -in "$cert" -inkey "$key" -name "$identity" \
    -passout env:P12_PASSWORD -out "$work/developer-id.p12"
rm -f "$work/all.p12" "$work/all.pem" "$work"/cert*.pem "$work"/key*.pem

printf 'Apple Account email: '
read -r apple_id
echo "App-specific password (create one at https://account.apple.com → Sign-In and Security → App-Specific Passwords)."
printf 'App-specific password: '
stty -echo
read -r app_password
stty echo
echo

echo "Checking the notarization credentials…"
if ! xcrun notarytool history --apple-id "$apple_id" --team-id "$team_id" \
        --password "$app_password" >/dev/null 2>&1; then
    echo "Apple rejected those credentials. Nothing was uploaded." >&2
    exit 1
fi

base64 -i "$work/developer-id.p12" | gh secret set MACOS_CERTIFICATE_P12 --repo "$REPO"
printf '%s' "$P12_PASSWORD" | gh secret set MACOS_CERTIFICATE_PASSWORD --repo "$REPO"
printf '%s' "$apple_id" | gh secret set APPLE_ID --repo "$REPO"
printf '%s' "$team_id" | gh secret set APPLE_TEAM_ID --repo "$REPO"
printf '%s' "$app_password" | gh secret set APPLE_APP_PASSWORD --repo "$REPO"

gh workflow run release.yml --repo "$REPO" --ref main
echo "Secrets saved and a signed build started: https://github.com/$REPO/actions"
