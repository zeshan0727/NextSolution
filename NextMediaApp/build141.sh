#!/bin/bash
set -euo pipefail

cat NextMediaApp/v141patch.part00 NextMediaApp/v141patch.part01 > NextMediaApp/v141patch.b64
git show HEAD^:NextMediaApp/build141.sh > /tmp/NextMedia-build141-core.sh
exec bash /tmp/NextMedia-build141-core.sh
