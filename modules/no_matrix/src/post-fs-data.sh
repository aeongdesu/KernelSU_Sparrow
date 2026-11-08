#!/system/bin/sh

MODDIR=$(dirname "$0")
. "$MODDIR/common.sh"

backup
patch
rule_add
