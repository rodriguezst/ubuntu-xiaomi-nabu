#!/bin/bash

# Exit on any error, undefined variable, or pipe failure
set -euo pipefail

REPO="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"
REF="linux-rolling-stable"
PREV_REF=$(sed -n 's/^KERNEL_BRANCH="\([^"]*\)".*/\1/p' nabu-kernel_build.sh)         
git clone --depth=1 -b $PREV_REF $REPO linux
cd linux
git config user.name 'github-actions[bot]'
git config user.email 'github-actions[bot]@users.noreply.github.com'
git am --whitespace=fix ../kernel-files/*.patch
rm -rf ../kernel-files/*.patch
git fetch --unshallow origin $REF:$REF
git rebase $REF
git log -1 $REF > ../RELEASE.md
git format-patch $REF --start-number=1 -o ../kernel-files -- . ':!arch/*/configs/*' > /dev/null
KERNVER=$(grep -E '^VERSION|^PATCHLEVEL|^SUBLEVEL' Makefile | \
    sed -E 's/[^0-9]*//g' | tr '\n' '.' | sed 's/\.$//' )
NEW_REF=v${KERNVER%.0}
sed -i 's/^KERNEL_BRANCH=.*/KERNEL_BRANCH='$NEW_REF'/' ../nabu-kernel_build.sh
cd ..
rm -rf linux
