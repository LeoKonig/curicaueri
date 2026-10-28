{
  description = "Curicaueri: Flor y Canto — entornos de desarrollo del prototipo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    hlib = pkgs.haskell.lib;

    # GHC 9.4 con las bibliotecas del núcleo ya registradas en su base de
    # paquetes global. Basta para compilar con `runghc Setup.hs` (README,
    # "sin cabal-install"). containers, text, bytestring, process, directory y
    # filepath vienen con GHC.
    ghc94Env = pkgs.haskell.packages.ghc94.ghcWithPackages (p: [
      p.aeson
      p.aeson-pretty
      p.scientific
      p.network
      p.hspec
      p.QuickCheck
    ]);

    # Los tres paquetes de Haskell, para `nix build` y `nix run`. Las pruebas
    # se desactivan aquí porque leen archivos fuera de nucleo/
    # (pruebas_compartidas/, datos/); corren con cabal o en la integración
    # continua.
    hp = pkgs.haskell.packages.ghc94.override {
      overrides = self: super: {
        motor  = hlib.dontCheck (self.callCabal2nix "motor" ./nucleo { });
        reglas = hlib.dontCheck (self.callCabal2nix "reglas" ./nucleo/reglas { });
        nucleo = self.callCabal2nix "nucleo" ./nucleo/app { };
      };
    };

    # Godot de nixpkgs se llama `godot` o `godot4` según la versión; las
    # pruebas lo buscan en $GODOT.
    exportarGodot = ''
      export GODOT="''${GODOT:-$(command -v godot4 || command -v godot || echo godot)}"
    '';

    linea = ''echo "=================================================="'';
  in {
    packages.${system} = {
      nucleo = hp.nucleo;
      default = hp.nucleo;
    };

    devShells.${system} = {

      # ------------------------------------------------------------
      # Todo el proyecto: núcleo, cliente, agentes e integración continua
      # ------------------------------------------------------------
      default = pkgs.mkShell {
        buildInputs = [
          ghc94Env
          pkgs.cabal-install
          # Descomenta para tener el servidor de lenguaje. Debe ser el de
          # GHC 9.4; si la caché no lo trae, se compila (tarda y ocupa).
          # (pkgs.haskell-language-server.override { supportedGhcVersions = [ "94" ]; })
          pkgs.godot_4          # cliente y sus pruebas sin interfaz
          pkgs.python3          # agente de Python y probar_agentes.sh
          pkgs.mercury          # agente de Mercury
          pkgs.actionlint       # revisar .github/workflows
          pkgs.git
          pkgs.zip
          pkgs.unzip
        ];
        env.LANG = "C.UTF-8";   # hspec escribe acentos; sin UTF-8 se cae
        shellHook = ''
          ${exportarGodot}
          ${linea}
          echo "Curicaueri: Flor y Canto — entorno completo"
          ${linea}
          echo "- GHC:     $(ghc --numeric-version)"
          echo "- cabal:   $(cabal --numeric-version)"
          echo "- Godot:   $($GODOT --version 2>/dev/null | head -n1)"
          echo "- Python:  $(python3 --version | cut -d' ' -f2)"
          echo "- Mercury: $(mmc --version 2>/dev/null | head -n1)"
          ${linea}
          echo "Compilar y probar el núcleo:  (cd nucleo && cabal build all && cabal test all)"
          echo "Pruebas del cliente:          NUCLEO=\$(cd nucleo && cabal list-bin nucleo) ./probar_cliente.sh"
          echo "Pruebas de los agentes:       NUCLEO=\$(cd nucleo && cabal list-bin nucleo) ./probar_agentes.sh"
          ${linea}
        '';
      };

      # ------------------------------------------------------------
      # Shells mínimas, para cuando hay poco espacio
      # ------------------------------------------------------------

      # Solo GHC con las bibliotecas: compila con `runghc Setup.hs` (README).
      nucleo = pkgs.mkShell {
        buildInputs = [ ghc94Env ];
        env.LANG = "C.UTF-8";
        shellHook = ''
          echo "Núcleo sin cabal-install — GHC $(ghc --numeric-version). Ver README: runghc Setup.hs …"
        '';
      };

      # GHC con las bibliotecas y cabal-install: `cabal build all`.
      haskell = pkgs.mkShell {
        buildInputs = [ ghc94Env pkgs.cabal-install ];
        env.LANG = "C.UTF-8";
        shellHook = ''
          echo "Núcleo con cabal — GHC $(ghc --numeric-version), cabal $(cabal --numeric-version)"
        '';
      };

      # Solo Godot: pruebas del cliente con un núcleo ya compilado
      # (NUCLEO=/ruta/al/nucleo ./probar_cliente.sh).
      cliente = pkgs.mkShell {
        buildInputs = [ pkgs.godot_4 ];
        shellHook = ''
          ${exportarGodot}
          echo "Cliente — $($GODOT --version 2>/dev/null | head -n1)"
        '';
      };

      # Solo Python: el agente de Python y probar_agentes.sh.
      agentes = pkgs.mkShell {
        buildInputs = [ pkgs.python3 ];
        shellHook = ''
          echo "Agentes — Python $(python3 --version | cut -d' ' -f2). NUCLEO=/ruta/al/nucleo ./probar_agentes.sh"
        '';
      };

      # Solo Mercury: compilar el agente (cd agentes/mercury && make).
      mercury = pkgs.mkShell {
        buildInputs = [ pkgs.mercury ];
        shellHook = ''
          echo "Mercury — $(mmc --version 2>/dev/null | head -n1)"
        '';
      };
    };
  };
}
