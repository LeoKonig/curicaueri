# Cómo contribuir

Gracias por interesarte en *Curicaueri: Flor y Canto*. Antes de enviar algo, lee esto.

## 1. Acepta el CLA

Para poder conservar la opción de publicar el juego también bajo otros términos (por ejemplo, una versión comercial), **solo se fusionan contribuciones de quien haya aceptado el [CLA](CLA.md)**. No te quita la titularidad de lo que escribas.

En tu primer *pull request*, escribe el comentario de aceptación que indica el CLA (sección 9). Sin eso, el PR no se fusiona. El registro es manual por ahora.

## 2. Qué licencia tiene lo que envías

Según la carpeta (ver [`LICENCIAS.md`](LICENCIAS.md)):

- **Código** (`nucleo/`, `cliente/`, `agentes/` y demás): GPL-3.0-or-later.
- **Datos** (`datos/`) y **documentación** (`docs/`): CC BY 4.0.

## 3. Reglas técnicas

El diseño manda: lee [`CLAUDE.md`](CLAUDE.md), `docs/arquitectura-prototipoV5.md` y `docs/arquitectura-funcional.md` antes de cambiar algo que no sea trivial. En resumen:

- Todo en español: código, comentarios, commits, documentos y textos visibles.
- Una rama por tema y un *pull request* contra `main`; no se empuja a `main` directamente.
- Un commit, una idea. Un cambio no está terminado hasta que pasan todas las pruebas y la integración continua.
- Si cambia una decisión de diseño, se actualizan V5 y el documento funcional en el mismo PR.
- Las afirmaciones históricas sin fuente llevan "por verificar".

## 4. Material de terceros, arte e inteligencia artificial

- **No subas arte, fuentes ni audio propietarios o de terceros** sin una licencia compatible. El arte de pago nunca entra a este repositorio.
- Si tu contribución incluye material de terceros, indica su origen y su licencia en el PR.
- Si usaste herramientas de IA generativa, indícalo en el PR.
