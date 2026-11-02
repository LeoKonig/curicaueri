# Licencias de Curicaueri: Flor y Canto

Copyright © 2026 Leonardo Arturo Gómez Garduño.

Este repositorio usa **licencias distintas según el tipo de contenido**. Cada carpeta dice cuál le toca; el texto completo de cada licencia está en el archivo `LICENSE` correspondiente.

| Parte | Dónde | Licencia | Texto |
| --- | --- | --- | --- |
| Código | `nucleo/`, `cliente/`, `agentes/`, `pruebas_compartidas/`, `hito_0/` (salvo lo indicado abajo), scripts y archivos de construcción (`flake.nix`, `probar_*.sh`) | GPL-3.0-or-later | [`LICENSE`](LICENSE) |
| Datos del juego | `datos/` | CC BY 4.0 | [`datos/LICENSE`](datos/LICENSE) |
| Documentación | `docs/`, `README.md` | CC BY 4.0 | [`docs/LICENSE`](docs/LICENSE) |
| Arte de pago (producto aparte) | No está en este repositorio | Licencia propietaria, aparte | — |
| Nombre y logotipo | — | Marca; no se licencian con lo anterior | [`MARCAS.md`](MARCAS.md) |

## Código: GPL-3.0-or-later

Este programa es software libre: puedes redistribuirlo y modificarlo bajo los términos de la Licencia Pública General de GNU, publicada por la Free Software Foundation, ya sea la versión 3 o (a tu elección) cualquier versión posterior.

Se distribuye con la esperanza de que sea útil, pero **sin ninguna garantía**, ni siquiera la garantía implícita de comerciabilidad o de idoneidad para un fin particular. Consulta la GPL para más detalles.

Identificador SPDX: `GPL-3.0-or-later`.

## Datos y documentación: CC BY 4.0

Puedes copiar, redistribuir y adaptar los datos y la documentación, incluso con fines comerciales, siempre que des crédito. Un crédito válido es:

> Curicaueri: Flor y Canto, © 2026 Leonardo Arturo Gómez Garduño, CC BY 4.0. https://github.com/LeoKonig/curicaueri

Se eligió CC BY (y no una licencia con "compartir igual") para que un paquete de datos o de arte pueda construirse sobre los datos del juego sin quedar obligado a abrirse. Los hechos históricos en sí no son propiedad de nadie; lo que se licencia es la forma en que están escritos y organizados aquí. Cada dato histórico lleva su `fuente` y las afirmaciones inciertas llevan "por verificar".

Identificador SPDX: `CC-BY-4.0`.

## Arte de pago: un producto independiente

Está previsto ofrecer paquetes de arte de pago como extra opcional. Para que el código libre y el arte de pago sigan siendo dos obras claramente independientes, se cumplen estas reglas:

1. **El juego funciona completo sin el arte de pago.** El código y los datos de este repositorio incluyen todo lo necesario con recursos libres.
2. **El arte se carga por id de recurso** desde un paquete configurable. Ningún archivo propietario se referencia como obligatorio en el código ni entra a este repositorio ni a los binarios publicados bajo GPL.
3. **Un paquete de arte no modifica ni se enlaza al código.** Solo aporta recursos (imágenes, audio) que el cliente carga por id. Se distribuye por separado (tienda o repositorio privado) y con su propia licencia.
4. **No se venden juntos como si fueran una sola obra.** El juego base y el paquete de arte son dos productos distintos.

## Qué conserva el titular

El titular de los derechos conserva la facultad de ofrecer su propio código y sus datos bajo otros términos, incluida una versión comercial. Por eso las contribuciones externas se aceptan solo bajo el [`CLA`](CLA.md). Las versiones ya publicadas bajo GPL y CC BY siguen disponibles bajo esas licencias para quienes las hayan recibido.

## Excepciones y terceros

- **`hito_0/support.js`** es un archivo generado por una herramienta externa (dice "GENERATED from dc-runtime"). **No está cubierto por la licencia del código** hasta confirmar su origen y su licencia. El prototipo HTML carga React y Babel desde unpkg al abrirse; no se incluyen en el repositorio y conservan sus propias licencias.
- Las **dependencias** (Godot, las bibliotecas de Haskell, etc.) conservan su licencia propia y no se incluyen en este repositorio.
- Quien redistribuya el proyecto debe conservar los avisos de copyright y de licencia de cada parte.
