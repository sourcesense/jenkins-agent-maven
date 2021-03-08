#!/usr/bin/env bash
scriptName=dep-bootstrap.sh
scriptVersion=0.3.1
>&2 echo "Running $scriptName version=$scriptVersion"

version="$1"
if [[ -z $version ]] ; then
    >&2 echo "usage: $scriptName <version> [parameters]"
    exit 1
fi
shift

targetDir="$HOME/.dep"
if [[ ! -d "$targetDir/bootstrap/$version" ]] ; then
    >&2 echo "bootstrap version $version not found"
    if [[ ! -d "$targetDir/git" ]] ; then
        >&2 echo "cloning dep-bootstrap repo tag $version in $targetDir/git"
        url=https://github.com/EcoMind/dep-bootstrap.git
        git -c advice.detachedHead=false clone --depth 1 --branch "$version" "$url" "$targetDir/git" || exit 1
    else
        >&2 echo "checking out dep-bootstrap repo tag $version in $targetDir/git"
        (cd "$targetDir/git" && git fetch --all --tags --prune -q && git reset --hard -q "tags/$version") || exit 1
    fi
    >&2 echo "copying bootstrap.sh in $targetDir/bootstrap/$version"
    mkdir -p "$targetDir/bootstrap/$version" || exit 1
    cp "$targetDir/git/bootstrap.sh" "$targetDir/bootstrap/$version" || exit 1
fi

>&2 echo "sourcing $targetDir/bootstrap/$version/bootstrap.sh"
# shellcheck disable=SC1090
. "$targetDir/bootstrap/$version/bootstrap.sh" "$@"