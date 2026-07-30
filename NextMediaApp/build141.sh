#!/bin/bash
set -euo pipefail

cat NextMediaApp/v141patch.part00 NextMediaApp/v141patch.part01 > NextMediaApp/v141patch.b64
git fetch --depth=1 origin f23b2f08015fdaf04826e147efd1906996824a87
git show FETCH_HEAD:NextMediaApp/build141.sh > /tmp/NextMedia-build141-core.sh
exec bash /tmp/NextMedia-build141-core.sh
