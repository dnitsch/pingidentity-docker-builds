#!/usr/bin/env sh

product="$1"
tags=$(docker images "pingidentity/${product}*" --format "{{.Tag}}" -q)
for tag in $tags ; do
  docker push pingidentity/"$product":"$tag"
done