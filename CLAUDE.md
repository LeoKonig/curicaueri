# Curicaueri: Flor y Canto — reglas para trabajar en este repositorio

Juego de gran estrategia de código abierto sobre el reino purépecha (1475–1530). Núcleo en Haskell (`nucleo/`: paquetes `motor`, `reglas` y la cáscara `app`) y cliente en Godot (`cliente/`). El diseño manda: `docs/arquitectura-prototipoV5.md` (qué es el juego) y `docs/arquitectura-funcional.md` (cómo se modela). Léelos antes de cambiar algo que no sea trivial.

## Idioma

Todo en español: código, comentarios, mensajes de commit, documentos y textos visibles. Los identificadores de Haskell y GDScript también (`designarMoneda`, `pasoDirector`).

## Compilar y probar

```sh
cd nucleo && cabal build all --enable-tests && cabal test all     # motor y reglas
NUCLEO="$(cd nucleo && cabal list-bin nucleo)" ./probar_agentes.sh
GODOT=/ruta/a/godot NUCLEO=... ./probar_cliente.sh               # espejo, protocolo, integración, decisiones
```

Sin cabal-install, con `runghc Setup.hs` (ver el README). Las pruebas necesitan una terminal en UTF-8 (`export LANG=C.UTF-8`). La integración continua (`.github/workflows/pruebas.yml`) corre todo con GHC 9.4 y 9.8, y con Godot 4.3 y 4.7.2. Un cambio no está terminado hasta que todo pasa.

`nucleo/cabal.project` fija `index-state` para que las dependencias no cambien solas. Para actualizarlas, sube esa fecha en un commit propio.

## Invariantes que no se rompen

1. **`motor` no importa `reglas`.** El motor no sabe nada de purépechas: se prueba con el juego de juguete de `nucleo/test/Spec.hs`. Solo entra al motor lo que V5 o el documento funcional exigen.
2. **Determinismo.** Nada de `Double` en el estado: `Fijo` (escala 10 000) o enteros. El azar sale de `rng σ nombre tick`. Los mapas se recorren por clave y los empates se rompen por id.
3. **Magnitudes con modificadores.** Los sistemas escriben la base o crean y terminan modificadores con fuente; nunca el valor efectivo. Cada magnitud tiene un solo escritor, salvo que se declare lo contrario. El desglose debe explicar cada número.
4. **Valores por defecto.** Todo campo nuevo tiene un valor por defecto con el que lo existente no cambia. Los guardados anteriores siguen cargando; si un cambio no puede cumplirlo, sube `versionGuardado` en un commit propio y `cargar` rechaza los anteriores con un aviso claro (V5, *Guardado*), mientras no haya migración ni partidas reales que conservar.
5. **Nada sin uso.** No se añaden campos, comandos ni archivos "por si acaso". Cada pieza entra con lo que la usa, con su ley o su prueba, y en el hito que le toca (tabla de *Hitos* en V5).
6. **Datos, no código.** Escenarios, guion, bienes, ejes y grupos son JSON validados al cargar, con todos los errores acumulados. Las condiciones usan el lenguaje cerrado del guion (`Motor.Guion`); no se inventan otros.
7. **El protocolo se escribe a mano.** Los nombres JSON viven en `Motor.Protocolo`, `Reglas.Comando` y `cliente/red/protocolo.gd`, y cada mensaje tiene su archivo dorado en `pruebas_compartidas/`. Si cambias el cable, actualiza los dorados a propósito y sube la versión cuando la compatibilidad lo pida.
8. **Rechazo sin daño.** Un comando o una respuesta rechazados no cambian el estado y vuelven con un motivo legible.

## Vocabulario fijado (no lo cambies sin cambiar V5)

- **Grupos de poder:** `nobleza_guerrera`, `administradores`, `sacerdocio`, `mercaderes`. No son facciones.
- **Facción:** unidad de decisión con centro, bolsa común y objetivos comunes (las tres preguntas de V5, *Qué es una facción*). No es "territorio, tesoro y títulos". Antes de 1530 los altépetl sujetos no son facciones.
- **Ejes de poder:** coerción, extracción, legitimidad (es `faccion.legitimidad`), administración y red, declarados en `datos/ejes.json`.
- **Moneda:** el tesoro y los costos se cuentan en unidades de valor. Con moneda designada, las magnitudes nominales (el tesoro) se cuentan en la moneda, y los flujos pasan por `enCuenta` al tipo del día. Ver V5, *La moneda designada y la inflación*.
- **Bienes como magnitudes de la facción:** `bien.<id>.existencias` y `bien.<id>.produccion`. Su escritor será el sistema de producción del paso 6 (hito 3).

## Cómo se trabaja

- **Una rama por tema** (`claude/<tema>`) y un pull request contra `main`. No se empuja a `main` directamente. Antes de empezar, trae `main` y las ramas abiertas para no duplicar trabajo; si otra rama toca lo mismo, construye encima de ella o coordina.
- **Un commit, una idea.** Si arreglas algo ajeno al tema (la integración continua, un error encontrado de paso), ponlo en un commit aparte y dilo en el PR.
- **Las propuestas externas se verifican** contra V5 y el código antes de adoptarlas. Los textos de otras IA suelen traer nombres que no existen o contradicciones con decisiones ya tomadas.
- **Documentos:** cuando cambie una decisión de diseño, actualiza V5 y el documento funcional en el mismo PR. Las afirmaciones históricas sin fuente llevan "por verificar".
- **No subas** compilados, cachés, `dist*/`, `cliente/.godot/` ni almacenes de Nix (`.nix-store/`).
