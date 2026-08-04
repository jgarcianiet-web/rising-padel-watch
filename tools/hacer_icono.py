#!/usr/bin/env python3
"""Genera los iconos de la app: pala de pádel perforada, en diagonal, con la pelota.

    pip install Pillow numpy
    python3 tools/hacer_icono.py

Escribe los dos PNG de 1024 directamente en los catálogos de assets. La variante
del reloj lleva la escena algo encogida porque watchOS recorta el icono en
círculo y lo que toca las esquinas desaparece.

Se dibuja a 4096 y se reduce a 1024 para que los bordes salgan suaves. Sin canal
alfa: App Store rechaza iconos de iOS con transparencia.
"""

import pathlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 4096
RAIZ = pathlib.Path(__file__).resolve().parent.parent

# Paleta: verde pista de fondo, pala clara para el contraste, pelota amarilla.
FONDO_CLARO = np.array([17, 138, 100], dtype=float)
FONDO_OSCURO = np.array([5, 47, 35], dtype=float)
PALA_MARCO = (250, 252, 251)
PALA_CARA = (228, 238, 233)
PELOTA = (217, 225, 76)
PELOTA_LUZ = (233, 240, 116)
PELOTA_COSTURA = (158, 168, 38)


def fondo() -> Image.Image:
    """Degradado diagonal con un brillo radial suave arriba a la izquierda."""
    y, x = np.mgrid[0:S, 0:S].astype(float) / S
    t = ((x + y) / 2)[..., None]
    base = FONDO_CLARO * (1 - t) + FONDO_OSCURO * t
    # El brillo evita que el fondo parezca un color plano en pantallas pequeñas.
    d = np.sqrt((x - 0.32) ** 2 + (y - 0.28) ** 2)
    brillo = np.clip(1 - d / 0.9, 0, 1)[..., None] * 26
    return Image.fromarray(np.clip(base + brillo, 0, 255).astype(np.uint8))


def capa_pala(escala: float) -> Image.Image:
    """La pala en vertical sobre una capa transparente; se rota después."""
    capa = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(capa)

    hx, hy = S * 0.5, S * 0.40
    rx, ry = S * 0.205 * escala, S * 0.225 * escala
    borde = S * 0.030 * escala

    # Mango primero, para que la cabeza tape la unión. Corto y ancho: el mango de
    # una pala de pádel es un puño, no el mango de una raqueta de tenis.
    mango_w = S * 0.095 * escala
    draw.rounded_rectangle(
        [hx - mango_w / 2, hy + ry * 0.72, hx + mango_w / 2, hy + ry * 0.72 + S * 0.185 * escala],
        radius=mango_w / 2,
        fill=PALA_MARCO,
    )
    # Marco y cara. La forma de pala de pádel es un óvalo casi redondo.
    draw.ellipse([hx - rx, hy - ry, hx + rx, hy + ry], fill=PALA_MARCO)
    draw.ellipse(
        [hx - rx + borde, hy - ry + borde, hx + rx - borde, hy + ry - borde],
        fill=PALA_CARA,
    )

    # Agujeros: rejilla hexagonal perforada hasta el fondo (se vacía el alfa).
    # Las filas se generan simétricas respecto al centro de la cara; si no, la
    # rejilla queda escorada hacia una esquina y se nota.
    alfa = np.array(capa.getchannel("A"))
    paso = S * 0.052 * escala
    radio_agujero = S * 0.0115 * escala
    yy, xx = np.mgrid[0:S, 0:S].astype(float)
    filas = int(ry * 0.62 * 2 / (paso * 0.87)) | 1  # impar: una fila pasa por el centro
    columnas = int(rx * 0.62 * 2 / paso) | 1
    for i in range(filas):
        cy = hy + (i - filas // 2) * paso * 0.87
        for j in range(-columnas // 2 - 1, columnas // 2 + 2):
            # Filas impares corridas medio paso: rejilla hexagonal. Como las
            # posiciones salen de offsets respecto al centro (±0.5, ±1.5…), la
            # rejilla queda simétrica en la cara.
            cx = hx + (j + (0.5 if i % 2 else 0)) * paso
            # Solo dentro de la cara, con margen para no morder el marco.
            norm = ((cx - hx) / (rx - borde * 2.6)) ** 2 + ((cy - hy) / (ry - borde * 2.6)) ** 2
            if norm < 0.92:
                agujero = (xx - cx) ** 2 + (yy - cy) ** 2 <= radio_agujero**2
                alfa[agujero] = 0
    capa.putalpha(Image.fromarray(alfa))

    return capa.rotate(-28, resample=Image.BICUBIC, center=(hx, S * 0.52))


def sombra_de(capa: Image.Image) -> Image.Image:
    """Sombra suave de la silueta, desplazada hacia abajo-derecha."""
    alfa = capa.getchannel("A").point(lambda v: v * 30 // 100)
    sombra = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    negro = Image.new("RGBA", (S, S), (3, 26, 19, 255))
    sombra.paste(negro, (int(S * 0.016), int(S * 0.030)), alfa)
    return sombra.filter(ImageFilter.GaussianBlur(S * 0.012))


def pelota(draw: ImageDraw.ImageDraw, escala: float) -> None:
    bx, by, br = S * 0.775, S * 0.225, S * 0.098 * escala
    draw.ellipse([bx - br, by - br, bx + br, by + br], fill=PELOTA)
    # Una sola costura, recortada dentro de la pelota.
    draw.arc(
        [bx - br * 2.35, by - br * 0.98, bx + br * 0.55, by + br * 0.98],
        start=-46, end=46, fill=PELOTA_COSTURA, width=int(br * 0.11),
    )
    # Punto de brillo pequeño arriba-izquierda; menos es más.
    draw.ellipse(
        [bx - br * 0.62, by - br * 0.68, bx - br * 0.22, by - br * 0.28], fill=PELOTA_LUZ
    )


def escena(escala: float) -> Image.Image:
    """La composición entera; `escala` encoge el contenido sin tocar el fondo."""
    img = fondo().convert("RGBA")
    pala = capa_pala(escala)
    img.alpha_composite(sombra_de(pala))
    img.alpha_composite(pala)
    pelota(ImageDraw.Draw(img), escala)
    return img.convert("RGB").resize((1024, 1024), Image.LANCZOS)


def main() -> None:
    destinos = [
        # (ruta, escala). El reloj encoge la escena para el recorte circular.
        (RAIZ / "ios/RisingPadel/Assets.xcassets/AppIcon.appiconset/AppIcon.png", 1.0),
        (RAIZ / "ios/RisingPadelWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png", 0.84),
    ]
    for ruta, escala in destinos:
        escena(escala).save(ruta)
        print(f"OK {ruta.relative_to(RAIZ)} (escala {escala})")


if __name__ == "__main__":
    main()
