#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash tests/run_tests.sh
bash tests/run_auth_tests.sh
bash tests/run_backup_tests.sh
bash tests/run_access_tests.sh
python3 -m unittest discover -s tests -p 'test_linux_security.py'
python3 -m unittest discover -s tests -p 'test_windows_privacy.py'
