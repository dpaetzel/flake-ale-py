{
  description = "BA flake";

  inputs = {
    # nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-21.11";

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.11";
    # nixpkgs.url =
    #   "github:NixOS/nixpkgs/bc5d68306b40b8522ffb69ba6cff91898c2fbbff";

    # This is where importlib-metadata was bumped to 4.10.0
    nixpkgs-importlib-metadata.url =
      "github:NixOS/nixpkgs/2a0966e8165fe41efe4d150dc0bd95c7b2d67256";

    mach-nix.url =
      # "github:DavHau/mach-nix/31b21203a1350bff7c541e9dfdd4e07f76d874be";
      "github:DavHau/mach-nix/";
    mach-nix.inputs.nixpkgs.follows = "nixpkgs";

    ale-py-source.url = "github:mgbellemare/Arcade-Learning-Environment/v0.7.4";
    ale-py-source.flake = false;
  };

  # outputs = inputs@{ self, nixpkgs, mach-nix, ale-py-source, nixpkgs-stable }:
  outputs = inputs@{ self, nixpkgs, mach-nix, ale-py-source
    , nixpkgs-importlib-metadata }:

    let
      system = "x86_64-linux";
      # pkgsStable = import nixpkgs-stable {
      #   inherit system;
      #   config.allowUnfree = true;
      # };
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      pkgsImportlibMetadata = import nixpkgs-importlib-metadata {
        inherit system;
        config.allowUnfree = true;
      };

      machNix = import mach-nix { pkgs = pkgs; };
      python = pkgs.python39;
      pythonStr = "python39";

      importlib-metadata =
        pkgsImportlibMetadata.${pythonStr}.pkgs.importlib-metadata;

      cudatoolkit = pkgs.cudaPackages.cudatoolkit_11_2;
      cudnn = pkgs.cudnn_cudatoolkit_11_2;
      nvidia = pkgs.linuxPackages.nvidia_x11;
      cc = pkgs.stdenv.cc.cc;
      magma = pkgs.magma.override { inherit cudatoolkit; };

    in rec {

      defaultPackage."${system}" = machNix.mkPython {
        # This requires a string and not a package set.
        python = pythonStr;

        # The file referenced here *must* be part of this flake (i.e. checked
        # into the same Git repository). Also, you *must* use a relative path.
        # requirements = builtins.readFile ./requirements.txt;
        requirements = "#";

        # Select providers for dependencies that should not be installed from
        # PyPI or conda (e.g. ones that rely on system libraries such as
        # cudatoolkit).
        providers.torch = "nixpkgs";
        # providers.numpy = "nixpkgs";

        # Non-Python dependencies.
        packagesExtra = [
          (machNix.buildPythonPackage {
            pname = "ale-py";
            version = "v0.7.4";
            src = ale-py-source;
            requirements = "#";
            nativeBuildInputs = with pkgs; [ cmake git ];
            propagatedBuildInputs = [ pkgs.zlib importlib-metadata ]
              ++ (with python.pkgs; [
                importlib-resources
                numpy
                markdown
                zipp
              ]);
            dontUseCmakeConfigure = true;
            # I think we have a similar problem like these ones
            #
            # - https://github.com/NixOS/nixpkgs/issues/75125
            #
            # - https://github.com/NixOS/nixpkgs/issues/84774
            #
            # The importlib-metadata package somehow isn't found by the
            # setup.py albeit being there. We thus simply remove that line from
            # setup.py as a dirty workaround.
            postPatch = ''
                sed -i "s/.*importlib-metadata.*//" setup.cfg
            '';
            patches = [
              ./0001-Fix-parse_version-in-setup.py.patch
              ./0001-Disable-SDL.patch
              # prevent CMake from trying to get libraries from the internet
              (pkgs.substituteAll {
                src = ./0001-Remove-pybind11-download.patch;
                pybind11_src = python.pkgs.pybind11.src;
              })
            ];
          })
        ];

        # Configure nixpkgs dependencies if necessary.
        overridesPost = [
          (final: prev: rec {
            tensorflow = prev.tensorflow-bin.override rec {
              cudaSupport = true;
              inherit cudnn cudatoolkit;
            };
            torch = prev.pytorch.override rec {
              cudaSupport = true;
              inherit cudnn cudatoolkit magma;
            };
          })
        ];
      };

      devShell."${system}" = pkgs.mkShell {
        shellHook = ''
          export LD_LIBRARY_PATH="${
            pkgs.lib.makeLibraryPath [ cc cudatoolkit cudnn nvidia cc ]
          }:$LD_LIBRARY_PATH";
            unset SOURCE_DATE_EPOCH
        '';
        buildInputs = [ (defaultPackage."${system}") ];
      };

    };
}
