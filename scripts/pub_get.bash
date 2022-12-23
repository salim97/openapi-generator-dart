#!/usr/bin/env bash

PWD=$(pwd)

for d in */ ; do
    if [ "$d" != "scripts/" ] 
    then
        echo "$PWD/$d"
        (cd "$PWD/$d" ; flutter pub get)
    fi
done