#!/usr/bin/env bash
scriptName=dep-bootstrap.sh
scriptVersion=2
repoURL=https://github.com/EcoMind/dep-bootstrap.git
targetDir="$HOME/.dep"

scriptErrorLabel="[ERROR IN $scriptName v.$scriptVersion]"
version="$1"
if [[ -z "$version" ]] ; then
    >&2 echo "$scriptErrorLabel usage: $scriptName <version> [parameters]"
    exit 1
fi
shift
if [ -z "$DEP_SOURCED" ] ; then
    gitDir="$targetDir/git"
    versionDir="$targetDir/bootstrap/$version"
    if [[ ! -d "$versionDir" ]] ; then
        if [[ $version == "local-SNAPSHOT" ]] ; then
            >&2 echo  "$scriptErrorLabel $versionDir not found. Please create it using following command (replacing '/path/to/my/local' part): 'mkdir -p $versionDir && ln -s /path/to/my/local/dep-bootstrap/bootstrap.sh $versionDir/bootstrap.sh'"
            exit 1
        fi
        if [[ ! -d "$gitDir" ]] ; then
            if ! git -c advice.detachedHead=false clone --depth 1 --branch "$version" "$repoURL" "$gitDir" -q ; then
                >&2 echo "$scriptErrorLabel error cloning repo '$repoURL' tag '$version' in '$gitDir'"
                exit 1
            fi
        else
            if ! (cd "$gitDir" && git fetch --all --tags --prune -q && git reset --hard -q "tags/$version") ; then
                >&2 echo "$scriptErrorLabel error checking out repo '$repoURL' tag '$version' in '$gitDir'"
                exit 1
            fi
        fi
        if ! mkdir -p "$versionDir" ; then
            >&2 echo "$scriptErrorLabel error creating dir '$versionDir'"
            exit 1
        fi
        bootstrapSource="$gitDir/bootstrap.sh"
        if ! cp "$bootstrapSource" "$versionDir" ; then
            >&2 echo "$scriptErrorLabel error copying '$bootstrapSource' into '$versionDir'"
            exit 1
        fi
    fi
    bootstrapTarget="$versionDir/bootstrap.sh"
    # shellcheck disable=SC1090
    if ! . "$bootstrapTarget" "$@" ; then
        >&2 echo "$scriptErrorLabel error sourcing '$bootstrapTarget'"
        exit 1
    fi
fi
