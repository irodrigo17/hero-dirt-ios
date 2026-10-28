# Pre-commit validation

Before creating a commit, run `bash scripts/check-ci.sh` and require it to succeed. This is the same localization, simulator build, and complete unit/UI test gate used by GitHub Actions. Keep the test suite intact when fixing failures. If the full check cannot finish, report the verification gap and leave the changes uncommitted.
