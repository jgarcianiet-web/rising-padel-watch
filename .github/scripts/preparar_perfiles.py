#!/usr/bin/env python3
"""Crea (o recrea) los perfiles de App Store y los instala en el runner.

Existe porque el archivado firma en modo manual. La firma automática de
xcodebuild archiva con un perfil de desarrollo, y un perfil de desarrollo exige
al menos un dispositivo registrado en el equipo (fallo del run #1). Forzar la
identidad de distribución sobre firma automática tampoco vale: Xcode lo rechaza
como configuración en conflicto (fallo del run #2).

Los perfiles de App Store no necesitan dispositivos, pero en modo manual
xcodebuild no los crea solo, así que se crean aquí contra la API de App Store
Connect con la misma clave que ya usa la subida.

Es idempotente: si el perfil ya existe se borra y se recrea, para que siempre
incluya los certificados de distribución vigentes.
"""

import base64
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # PyJWT

API = "https://api.appstoreconnect.apple.com"
KEY_ID = os.environ["APPSTORE_KEY_ID"]
ISSUER_ID = os.environ["APPSTORE_ISSUER_ID"]
KEY_PATH = os.environ["APPSTORE_KEY_PATH"]

# (bundle id, nombre del App ID si hay que crearlo, nombre del perfil, capabilities).
# Los nombres de perfil tienen que coincidir con PROVISIONING_PROFILE_SPECIFIER en
# ios/project.yml y con provisioningProfiles en el ExportOptions del workflow.
TARGETS = [
    ("com.risingpadel.watch", "Rising Padel", "RisingPadel AppStore", []),
    (
        "com.risingpadel.watch.watchkitapp",
        "Rising Padel Watch",
        "RisingPadelWatch AppStore",
        # Sin la capability, el perfil no incluye el entitlement de HealthKit que
        # declara la app del reloj y la firma falla al validar.
        ["HEALTHKIT"],
    ),
]

# Xcode 16+ busca los perfiles en la ruta nueva; las versiones anteriores en la
# clásica. Se escriben en las dos y así da igual qué Xcode lleve el runner.
INSTALL_DIRS = [
    pathlib.Path.home() / "Library/MobileDevice/Provisioning Profiles",
    pathlib.Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
]


def token() -> str:
    now = int(time.time())
    key = pathlib.Path(KEY_PATH).read_text()
    return jwt.encode(
        {"iss": ISSUER_ID, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": KEY_ID},
    )


def call(method: str, path: str, payload=None):
    request = urllib.request.Request(API + path, method=method)
    request.add_header("Authorization", "Bearer " + token())
    body = None
    if payload is not None:
        request.add_header("Content-Type", "application/json")
        body = json.dumps(payload).encode()
    try:
        with urllib.request.urlopen(request, body) as response:
            raw = response.read()
    except urllib.error.HTTPError as error:
        # El cuerpo del error de la API dice exactamente qué ha pasado; sin él,
        # depurar esto a ciegas desde CI es imposible.
        detail = error.read().decode(errors="replace")
        sys.exit(f"{method} {path} -> HTTP {error.code}\n{detail}")
    return json.loads(raw) if raw else {}


def distribution_certificate_ids() -> list:
    data = call("GET", "/v1/certificates?limit=200")["data"]
    ids = [
        cert["id"]
        for cert in data
        if cert["attributes"]["certificateType"] in ("DISTRIBUTION", "IOS_DISTRIBUTION")
    ]
    if not ids:
        sys.exit(
            "La cuenta no tiene ningún certificado de distribución. "
            "Crea uno de tipo 'Apple Distribution' (ver docs/testflight.md) "
            "y súbelo también como secreto BUILD_CERTIFICATE_BASE64."
        )
    return ids


def ensure_bundle_id(identifier: str, name: str) -> str:
    quoted = urllib.parse.quote(identifier)
    found = call("GET", f"/v1/bundleIds?filter[identifier]={quoted}&limit=200")["data"]
    # El filtro de la API hace coincidencia parcial; hay que comparar exacto para
    # que `com.risingpadel.watch` no dé por bueno `com.risingpadel.watch.watchkitapp`.
    for item in found:
        if item["attributes"]["identifier"] == identifier:
            return item["id"]
    created = call(
        "POST",
        "/v1/bundleIds",
        {
            "data": {
                "type": "bundleIds",
                "attributes": {"identifier": identifier, "name": name, "platform": "IOS"},
            }
        },
    )
    print(f"App ID creado: {identifier}")
    return created["data"]["id"]


def ensure_capability(bundle_internal_id: str, capability: str) -> None:
    current = call(
        "GET", f"/v1/bundleIds/{bundle_internal_id}/bundleIdCapabilities?limit=200"
    )["data"]
    if any(item["attributes"]["capabilityType"] == capability for item in current):
        return
    call(
        "POST",
        "/v1/bundleIdCapabilities",
        {
            "data": {
                "type": "bundleIdCapabilities",
                "attributes": {"capabilityType": capability},
                "relationships": {
                    "bundleId": {"data": {"type": "bundleIds", "id": bundle_internal_id}}
                },
            }
        },
    )
    print(f"Capability {capability} activada")


def recreate_profile(name: str, bundle_internal_id: str, certificate_ids: list) -> None:
    quoted = urllib.parse.quote(name)
    existing = call("GET", f"/v1/profiles?filter[name]={quoted}&limit=200")["data"]
    for profile in existing:
        call("DELETE", f"/v1/profiles/{profile['id']}")

    created = call(
        "POST",
        "/v1/profiles",
        {
            "data": {
                "type": "profiles",
                "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
                "relationships": {
                    "bundleId": {"data": {"type": "bundleIds", "id": bundle_internal_id}},
                    "certificates": {
                        "data": [{"type": "certificates", "id": c} for c in certificate_ids]
                    },
                },
            }
        },
    )
    attributes = created["data"]["attributes"]
    content = base64.b64decode(attributes["profileContent"])
    filename = f"{attributes['uuid']}.mobileprovision"
    for directory in INSTALL_DIRS:
        directory.mkdir(parents=True, exist_ok=True)
        (directory / filename).write_bytes(content)
    print(f"Perfil instalado: {name} ({attributes['uuid']})")


def main() -> None:
    certificates = distribution_certificate_ids()
    print(f"Certificados de distribución en la cuenta: {len(certificates)}")
    for identifier, app_name, profile_name, capabilities in TARGETS:
        bundle = ensure_bundle_id(identifier, app_name)
        for capability in capabilities:
            ensure_capability(bundle, capability)
        recreate_profile(profile_name, bundle, certificates)


if __name__ == "__main__":
    main()
