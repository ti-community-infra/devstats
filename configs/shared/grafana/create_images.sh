#!/bin/bash
# ARTWORK
# This script assumes that You have cncf/artwork cloned in ~/dev/cncf/artwork 
# This script assumes that You have cncf/artwork cloned in ~/dev/cdfoundation/artwork 
. ./devel/all_projs.sh || exit 2
for proj in $all
do
  suff=$proj
  icon=$proj
  mid="icon"
  icontype=`./devel/get_icon_type.sh "$proj"` || exit 1
  iconorg=`./devel/get_icon_source.sh "$proj"` || exit 4
  path=$icon
  if ( [ "$path" = "devstats" ] || [ "$path" = "cncf" ] || [ "$path" = "gitopswg" ] )
  then
    path="other/$icon"
  elif [ "$iconorg" = "cncf" ]
  then
    path="projects/$icon"
  fi
  cp "$HOME/dev/$iconorg/artwork/$path/icon/$icontype/$icon-$mid-$icontype.svg" "grafana/img/$suff.svg" || exit 2
  convert "$HOME/dev/$iconorg/artwork/$path/icon/$icontype/$icon-$mid-$icontype.png" -resize 32x32 "grafana/img/${suff}32.png" || exit 3
done

echo 'OK'
