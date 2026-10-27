{
  description = "Marinara Engine AI frontend";

  inputs = {
    flake-lib.url = "github:jgus-org/flake-lib/v1";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    {
      self,
      flake-lib,
      nixpkgs,
      ...
    }:
    flake-lib.lib.eachDefaultLinuxSystem (
      system:
      let
        pin = import ./pin.nix;
        inherit (pin)
          pnpmDepsHash
          pnpmHash
          pnpmVersion
          sourceHash
          sourceRev
          version
          ;
        pkgs = import nixpkgs {
          inherit system;
        };
        inherit (pkgs) lib;
        orgFormatting = flake-lib.lib.mkFormatting {
          inherit self system;
        };
        pnpm = pkgs.pnpm_10_latest.override {
          hash = pnpmHash;
          version = pnpmVersion;
        };
        source = {
          owner = "Pasta-Devs";
          repo = "Marinara-Engine";
          type = "github";
        };
        runtimePrograms = [
          pkgs.bubblewrap
          pnpm
          pkgs.python3
        ];
        runtimeLibraries = [
          pkgs.stdenv.cc.cc.lib
          pkgs.openssl
          pkgs.vulkan-loader
        ];

        marinara = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
          inherit version;
          buildPhase = ''
            runHook preBuild

            pnpm rebuild esbuild sharp onnxruntime-node protobufjs
            pnpm build
            pnpm install --offline --prod --ignore-scripts --frozen-lockfile
            pnpm rebuild sharp onnxruntime-node protobufjs

            runHook postBuild
          '';
          doInstallCheck = true;
          env.NODE_OPTIONS = "--max-old-space-size=4096";
          installCheckPhase = ''
            runHook preInstallCheck

            env \
              MARINARA_REQUIRE_PATH="''${out}/lib/marinara-engine/packages/server/package.json" \
              ${lib.getExe pkgs.nodejs_24} --input-type=module --eval \
                "import { createRequire } from 'node:module'; const require = createRequire(process.env.MARINARA_REQUIRE_PATH); require('sharp'); require('onnxruntime-node');"

            runHook postInstallCheck
          '';
          installPhase = ''
            runHook preInstall

            APP_ROOT=''${out}/lib/marinara-engine
            mkdir -p ''${APP_ROOT}/packages ''${APP_ROOT}/scripts ''${out}/bin

            cp package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ''${APP_ROOT}/
            cp -R .pnpm node_modules ''${APP_ROOT}/

            for PACKAGE in shared server client; do
              mkdir -p ''${APP_ROOT}/packages/''${PACKAGE}
              cp packages/''${PACKAGE}/package.json ''${APP_ROOT}/packages/''${PACKAGE}/
              cp -R packages/''${PACKAGE}/dist packages/''${PACKAGE}/node_modules ''${APP_ROOT}/packages/''${PACKAGE}/
            done

            cp scripts/install-backgroundremover.mjs scripts/protect-launcher-data.mjs ''${APP_ROOT}/scripts/
            cp -R docs ''${APP_ROOT}/
            cp README.md ''${APP_ROOT}/

            makeWrapper ${lib.getExe pkgs.nodejs_24} ''${out}/bin/marinara-engine \
              --add-flags "''${APP_ROOT}/packages/server/dist/index.js" \
              --chdir "''${APP_ROOT}" \
              --prefix PATH : ${lib.makeBinPath runtimePrograms} \
              --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibraries}:/usr/lib

            runHook postInstall
          '';
          meta = {
            description = "AI chat, roleplay, and game frontend";
            homepage = "https://github.com/Pasta-Devs/Marinara-Engine";
            license = lib.licenses.agpl3Plus;
            mainProgram = "marinara-engine";
            platforms = flake-lib.lib.defaultLinuxSystems;
          };
          nativeBuildInputs = [
            pkgs.makeWrapper
            pkgs.nodejs_24
            pkgs.pnpmConfigHook
            pnpm
          ];
          passthru.runtimeRootfs =
            (pkgs.buildFHSEnv {
              name = "marinara-engine-runtime";
            }).fhsenv;
          pname = "marinara-engine";
          pnpmDeps = pkgs.fetchPnpmDeps {
            inherit (finalAttrs) pname src version;
            inherit pnpm;
            fetcherVersion = 4;
            hash = pnpmDepsHash;
            nativeBuildInputs = [ pkgs.nodejs_24 ];
            prePnpmInstall = ''
              substituteInPlace .npmrc --replace-fail "store-dir=.pnpm-store" ""
            '';
          };
          postPatch = ''
            substituteInPlace packages/server/src/services/sandbox/bubblewrap-runtime.ts \
              --replace-fail \
                'const BWRAP_CANDIDATES = [' \
                'const BWRAP_CANDIDATES = ["${lib.getExe pkgs.bubblewrap}", '
            substituteInPlace packages/server/src/services/sidecar/sidecar-runtime.service.ts \
              --replace-fail \
                '["/usr/lib/libvulkan.so", "/usr/lib64/libvulkan.so", "/usr/lib/x86_64-linux-gnu/libvulkan.so.1"]' \
                '["${pkgs.vulkan-loader}/lib/libvulkan.so.1", "/usr/lib/libvulkan.so", "/usr/lib64/libvulkan.so", "/usr/lib/x86_64-linux-gnu/libvulkan.so.1"]'
          '';
          prePnpmInstall = ''
            substituteInPlace .npmrc --replace-fail "store-dir=.pnpm-store" ""
          '';
          src = pkgs.fetchFromGitHub {
            inherit (source) owner repo;
            hash = sourceHash;
            rev = sourceRev;
          };
        });
      in
      {
        checks.formatting = orgFormatting.check;
        formatter = orgFormatting.formatter;
        packages = {
          inherit marinara;
          default = marinara;
          update-branches = flake-lib.lib.mkUpdateBranches {
            inherit pkgs source;
            extraHashes = [
              "pnpmVersion"
              "pnpmHash"
            ];
            minimumTrackingVersion = "2.4.3";
            pinSchema = "github-pnpm";
          };
          update-version = flake-lib.lib.mkUpdateVersion {
            inherit pkgs source;
            artifactHook = lib.getExe (
              pkgs.writeShellApplication {
                name = "marinara-pnpm-pin";
                runtimeInputs = [
                  pkgs.gh
                  pkgs.jq
                  pkgs.nix
                ];
                text = ''
                  PACKAGE_JSON="$(gh api "/repos/''${GH_OWNER}/''${GH_REPO}/contents/package.json?ref=''${NEW_REV}" -H "Accept: application/vnd.github.raw")"
                  PNPM_VERSION="$(jq -r '(.packageManager // "") | select(startswith("pnpm@")) | split("@")[1] | split("+")[0]' <<<"''${PACKAGE_JSON}")"
                  if [[ -z "''${PNPM_VERSION}" ]]; then
                    echo "Marinara package.json declares no pnpm packageManager version" >&2
                    exit 1
                  fi
                  PNPM_HASH="$(nix store prefetch-file --json --hash-type sha256 "https://registry.npmjs.org/pnpm/-/pnpm-''${PNPM_VERSION}.tgz" | jq -r .hash)"
                  printf 'pnpmVersion=%s\npnpmHash=%s\n' "''${PNPM_VERSION}" "''${PNPM_HASH}"
                '';
              }
            );
            buildFailureHash = "pnpmDepsHash";
            extraHashes = [
              "pnpmVersion"
              "pnpmHash"
            ];
          };
        };
      }
    );
}
