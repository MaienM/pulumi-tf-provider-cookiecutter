{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { nixpkgs, flake-utils, ... }@inputs: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      poetry2nix = inputs.poetry2nix.lib.mkPoetry2Nix {
        inherit pkgs;
      };

      cruft = poetry2nix.mkPoetryApplication {
        projectDir = pkgs.fetchFromGitHub {
          owner = "Chilipp";
          repo = "cruft";
          rev = "d829bccec3bf690fe24387a1810795a05dd650c1";
          sha256 = "sha256-Up/r4e6jO5t5rTly05OpvHnuuyxxSJhNappq6kg51Zk=";
        };
        preferWheels = true;
        overrides = poetry2nix.overrides.withDefaults (_: super: {
          mkdocs-material = super.mkdocs-material.overridePythonAttrs (old: {
            postPatch = ''
              touch pyproject.toml
              ${old.postPatch or ""}
            '';
          });
        });
      };

      cruft-config-template = builtins.toFile "init.json" (builtins.toJSON {
        terraform_provider_name = "NAME";
        terraform_provider_org = "org";
        terraform_provider_version_or_commit = "0.0.0";
        terraform_provider_package_name = "internal/provider";
        terraform_sdk_version = "plugin-framework";
        provider_category = "utility";
        provider_naming_strategy = "explicit_modules";
      });
      cruft-init = pkgs.writeShellApplication {
        name = "cruft-init";
        runtimeInputs = [ cruft pkgs.go ];
        text = ''
          if [ "$(git ls-files | wc -l)" -gt 0 ]; then
            >&2 echo "Directory must be empty."
            exit 1
          fi

          if ! [ -f init.json ]; then
            cp "${cruft-config-template}" init.json

            name="''${PWD##*/}"
            name="''${name#pulumi-}"
            chmod +w init.json
            sed -i "s/NAME/$name/" init.json

            echo "Edit init.json and re-run cruft-init."
            exit 0
          fi

          rm -rf .gitignore sdk
          git reset .
          git clean -df -e init.json

          cruft create \
            https://github.com/MaienM/pulumi-tf-provider-cookiecutter \
            --output-dir=output \
            --extra-context='{"terraform_provider_name":"'"$name"'"}' \
            --extra-context-file=init.json \
            "$@"

          mv output/*/* .
          mv output/*/.* .
          rmdir output/*

          git add flake.nix
          nix flake lock

          git add .
          git reset init.json

          echo "Project initialized, you can now commit and proceed to test/tweak things."
          echo '> git commit -m "Init with cookiecutter template"'
        '';
      };

      make = pkgs.writeShellApplication {
        name = "make";
        runtimeInputs = with pkgs; [ gnumake ];
        text = ''
          make "$@" SHELL=${pkgs.bash}/bin/bash
        '';
      };
    in
    {

      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [

          # Base
          cruft
          cruft-init
          make
          pulumi
          pulumictl

          # NodeJS
          nodejs
          nodejs.pkgs.yarn
          typescript

          # Python
          (python3.withPackages (pkgs: with pkgs; [
            packaging
            setuptools
          ]))

          # Go
          go
          golangci-lint
          gopls

          # Dotnet
          dotnet-sdk

          # Java
          (callPackage gradle-packages.gradle_8 {
            java = jdk11;
          })

        ];
      };
    }
  );
}
