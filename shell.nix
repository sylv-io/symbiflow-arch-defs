{ pkgs ? import <nixpkgs> { } }:
with pkgs;
let
  pyEnv =
    let
      py = python3;
      hilbertcurve = with python3Packages;
        buildPythonPackage rec {
          version = "1.0.3";
          pname = "hilbertcurve";
          src = python3Packages.fetchPypi {
            inherit pname version;
            sha256 = "07cmxs9w2ch4a4d3fxp9nsjxpw2wqma4j41x17pl6s5jy501y16b";
          };
        };
      pycapnp = with python3Packages;
        buildPythonPackage rec {
          version = "0.6.4";
          pname = "pycapnp";
          src =
            fetchFromGitHub {
              owner = "capnproto";
              repo = "pycapnp";
              rev = "v1.0.0b2";
              sha256 = "0yh92bdlx1cbznp9ikiyv0qp6axqb8blyj7xc4ikisld4carcvd7";
            };
          dontUseCmakeConfigure = true;
          nativeBuildInputs = [ ];
          buildInputs = [ cmake pkgconfig ];
          propagatedBuildInputs = [ cython pypandoc capnproto-v8 ];
          setupPyGlobalFlags = [ "--force-system-libcapnp" ];
          doCheck = false;
        };
      sdf-timing = with python3Packages;
        let
          pyjson = buildPythonPackage rec {
            version = "1.3.0";
            pname = "pyjson";
            src = python3Packages.fetchPypi {
              inherit pname version;
              sha256 = "0a4nkmc9yjpc8rxkqvf3cl3w9hd8pcs6f7di738zpwkafrp36grl";
            };
          };
        in
        buildPythonPackage rec {
          pname = "python-sdf-timing";
          version = "unstable-2020-05-26";
          src = fetchFromGitHub {
            owner = "SymbiFlow";
            repo = "python-sdf-timing";
            rev = "0afbbfe5cec97330b3261d811a4d604a471a5d98";
            sha256 = "0crqa6k9ih1ngnzdrmx6yghb9zq530y2rjb4qflpqlwcvbhfg2n5";
          };
          propagatedBuildInputs = [ pyjson pytest pytestrunner yapf ply ];
        };
    in
    py.withPackages (ps: with ps; [
      virtualenv
      lxml
      progressbar2
      simplejson
      pyjson5
      svgwrite
      cairosvg
      GitPython
      matplotlib
      scipy
      flake8
      pytest
      yapf
      intervaltree
      numpy
      sdf-timing
      hilbertcurve
      pycapnp
    ]);

  capnproto-v8 = capnproto.overrideAttrs (
    old: rec {
      version = "0.8.0";
      src = fetchurl {
        url = "https://capnproto.org/capnproto-c++-${version}.tar.gz";
        sha256 = "03f1862ljdshg7d0rg3j7jzgm3ip55kzd2y91q7p0racax3hxx6i";
      };
    }
  );

  pinned-yosys =
    let
      hq-yosys-abc-verifier = abc-verifier.overrideAttrs (
        old: rec {
          version = "unstable-2020-10-02";
          src = fetchFromGitHub {
            owner = "YosysHQ";
            repo = "abc";
            rev = "623b5e82513d076a19f864c01930ad1838498894";
            sha256 = "1mrfqwsivflqdzc3531r6mzp33dfyl6dnqjdwfcq137arqh36m67";
          };
          passthru.rev = src.rev;
        }
      );
    in
    (
      yosys.overrideAttrs (
        old: rec {
          version = "unstable-2019-12-06";
          src = fetchFromGitHub {
            owner = "YosysHQ";
            repo = "yosys";
            rev = "8fe9c84e6c6a17e88ad623f6964bdde7be8f8481";
            sha256 = "02a3mmfrsdvjv04csx706w7lgc0rw2ywvnli477b8mg1zhz3a62l";
          };
          postBuild = ''
            patchShebangs yosys-config
          '';
        }
      )
    ).override {
      abc-verifier = hq-yosys-abc-verifier;
    };

  yosys-symbiflow-plugins = stdenv.mkDerivation {
    name = "yosys-symbiflow-plugins";
    version = "unstable-2020-06-09";
    src = fetchFromGitHub {
      owner = "SymbiFlow";
      repo = "yosys-symbiflow-plugins";
      rev = "e04ea5ba3f67be92cb42253015d33e102df306c2";
      sha256 = "0najv9lzidp2zw6nw605l6q6cs84gc9ishxdpsxapyn4aajjba73";
    };
    buildInputs = [ pinned-yosys readline zlib ];
    buildPhase = ''
      make plugins
    '';
    doCheck = false;
    installPhase = ''
      mkdir -p $out/share/yosys/plugins/
      for plugin in "*-plugin/*.so"
      do
        cp $plugin $out/share/yosys/plugins/
      done
    '';
  };

  pinned-yosys-with-plugins =
    pinned-yosys.overrideAttrs (
      old: rec {
        fixupPhase = ''
          mkdir -p $out/share/yosys/plugins/
          for plugin in "${yosys-symbiflow-plugins}/share/yosys/plugins/*.so"; do
            ln -snf $plugin $out/share/yosys/plugins/
          done
        '';
      }
    );

  pinned-vtr =
    stdenv.mkDerivation rec {
      name = "verilog-to-routing";
      version = "unstable-2020-05-27";
      src = fetchFromGitHub {
        owner = "SymbiFlow";
        repo = "vtr-verilog-to-routing";
        rev = "8980e46218542888fac879961b13aa7b0fba8432";
        sha256 = "1sq7f1f3dzfm48a9vq5nvp0zllby0nasm3pvqab70f4jaq0m1aaa";
      };
      nativeBuildInputs = [ cmake pkgconfig ];
      buildInputs = [ openocd bison flex ];
      enableParallelBuilding = true;
      fixupPhase = ''
        for capnp in "${capnproto-v8}/include/capnp/*.capnp"
        do
          cp $capnp $out/capnp
        done
      '';
    };

  #capnp-schema = stdenvNoCC.mkDerivation rec {
  #  name = "capnp-schema";
  #  builder = pkgs.writeText "builder.sh" ''
  #    source $stdenv/setup
  #    mkdir -p $out/capnp
  #    for capnp in "${pinned-vtr}/capnp/* ${capnproto-v8}/include/capnp/*.capnp"
  #    do
  #      cp $capnp $out/capnp
  #    done
  #  '';
  #};

  tinyfpgab = with python3Packages;
    let
      pyserial = buildPythonPackage rec {
        version = "3.4";
        pname = "pyserial";
        src = python3Packages.fetchPypi {
          inherit pname version;
          sha256 = "09y68bczw324a4jb9a1cfwrbjhq179vnfkkkrybbksp0vqgl0bbf";
        };
        doCheck = false;
      };
    in
    buildPythonPackage rec {
      version = "1.1.0";
      pname = "tinyfpgab";
      src = python3Packages.fetchPypi {
        inherit pname version;
        sha256 = "1dmpcckz7ibkl30v58wc322ggbcw7myyakb4j6fscm6xav23k4bg";
      };
      propagatedBuildInputs = [ pyserial ];
    };

in
(buildFHSUserEnv rec {
  name = "SymbiFlow";
  targetPkgs = pkgs: with pkgs;
    [
      pyEnv
      git
      cmake
      gcc
      clang
      gnumake
      pkg-config
      wget
      pinned-yosys-with-plugins
      pinned-vtr
      openocd
      nextpnr
      libxslt
      libxml2
      nodejs
      verilog
      fasm-bin
      icestorm
      tinyfpgab
      tinyprog
      xc3sprog
      readline
      capnproto-v8

      zlib
      binutils
      xxd
      sqlite-interactive
      libftdi
      fasm
      gtkwave
      pipenv
      which
      ncurses
      glib
      ncurses5
      glibc
      tcl
    ];
  runScript = ''
    bash --rcfile <(cat /etc/static/bashrc; PS1="\n\[\033[1;36m\][\[\e]0;\u@\h: \w\a\]\u@\h:\w]\\$\[\033[0m\] ")
  '';
  profile =
    ''
      export FHS_USER_ENV=true
      export YOSYS="${pinned-yosys-with-plugins}/bin/yosys";
      export YOSYS_DATADIR="${pinned-yosys-with-plugins}/share/yosys";
      export VPR="${pinned-vtr}/bin/vpr";
      export VPR_CAPNP_SCHEMA_DIR="//${pinned-vtr}/capnp";
      export GENFASM="${pinned-vtr}/bin/genfasm";
      export MAKE_FLAGS="-DUSE_CONDA=FALSE";
      export CMAKE_FLAGS="-DUSE_CONDA=FALSE -DYOSYS_DATADIR=$YOSYS_DATADIR -DVPR_CAPNP_SCHEMA_DIR=$VPR_CAPNP_SCHEMA_DIR";
    '';
}).env
