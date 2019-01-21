{ lib, stdenv, makeWrapper, writeScriptBin, coreutils, gawk
, electron3
, frontend
, daedalus-bridge
, daedalus-configs
, version
}:

let
  update-runner = writeScriptBin "update-runner" ''
    #!/bin/sh

    if [ -z "$1" ]; then
      echo "usage: update-runner UPDATE_FILE"
      exit 0
    fi

    if [ ! -e "$1" ]; then
      echo "There is no update file: $1"
      exit 1
    fi

    echo "Not updating because Daedalus is running from the immutable Nix store."
    exit 6
  '';

  daedalus-frontend = writeScriptBin "daedalus-frontend" ''
    #!/bin/sh
    exec ${electron3}/bin/electron ${frontend}/share/daedalus/main/
  '';

  daedalus-launcher = writeScriptBin "daedalus" ''
    #!/usr/bin/env bash
    set -euo pipefail

    export PATH="${lib.makeBinPath [ coreutils gawk ]}:$PATH"
    prefix="$(dirname $(dirname $(realpath $0)))"
    export PATH="$prefix/libexec:$PATH"

    if ! grep sse4 /proc/cpuinfo -q; then
      echo "ERROR: your cpu lacks SSE4 support, cardano will not work"
      exit 1
    fi

    # Choose network based on program name
    if [[ "$0" =~ -testnet$ ]]; then
      NETWORK=testnet
      ICON=daedalus-testnet
    elif [[ "$0" =~ -staging$ ]]; then
      NETWORK=staging
      ICON=daedalus-staging
    else
      NETWORK=mainnet
      ICON=daedalus
    fi
    export NETWORK

    test -z "''${XDG_DATA_HOME:-}" && { XDG_DATA_HOME="''${HOME}/.local/share"; }
    export CLUSTER=$NETWORK
    export DAEDALUS_DIR="''${XDG_DATA_HOME}/Daedalus"
    export DAEDALUS_CONFIG="$prefix/share/daedalus/$NETWORK"
    export REPORT_URL="$(awk '/reportServer:/ { print $2; }' $DAEDALUS_CONFIG/launcher-config.yaml)"

    mkdir -p "''${DAEDALUS_DIR}/$NETWORK/"
    cd "''${DAEDALUS_DIR}/$NETWORK/"
    mkdir -p Secrets Logs/pub

    # Daedalus looks in runtime directory for an icon
    cp -f $prefix/share/icons/hicolor/64x64/apps/$ICON.png icon.png
    cp -f $prefix/share/icons/hicolor/1024x1024/apps/$ICON.png icon_large.png

    # Note: there's not much logging from electron
    exec cardano-launcher --config "$DAEDALUS_CONFIG/launcher-config.yaml"
  '';

  backendName = "cardano-sl-${daedalus-bridge.version}";

in
  stdenv.mkDerivation {
    name = "daedalus-${version}-${backendName}";
    inherit version;
    buildInputs = [ makeWrapper ];
    buildCommand = ''
      mkdir -p $out/bin $out/share/daedalus $out/libexec $out/share/daedalus
      ln -s ${daedalus-bridge}/bin/* ${daedalus-frontend}/bin/* ${update-runner}/bin/* $out/libexec
      cp ${daedalus-launcher}/bin/daedalus $out/bin
      ln -s daedalus $out/bin/daedalus-testnet
      ln -s daedalus $out/bin/daedalus-staging
    '' + lib.concatStringsSep "\n" (lib.mapAttrsToList (network: cfg: ''
      ln -s ${cfg} $out/share/daedalus/${network}
    '') daedalus-configs);

    meta = with stdenv.lib; {
      description = "Ada wallet for the Cardano SL blockchain";
      homepage = https://daedaluswallet.io/;
      maintainers = [{
        email = "devops@iohk.io";
        github = "input-output-hk";
        name = "IOHK DevOps";
      }];
      license = licenses.mit;
      platforms = platforms.unix;
    };
  }
