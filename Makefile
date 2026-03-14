VERSION := $(shell grep 'VERSION=' smart-ssh | head -1 | sed 's/VERSION=//;s/"//g')

# Detect sha256 tool portably (macOS uses shasum, Linux uses sha256sum)
SHA256 := $(shell command -v sha256sum 2>/dev/null || command -v shasum 2>/dev/null)
ifeq ($(findstring shasum,$(SHA256)),shasum)
  SHA256_CMD := shasum -a 256
  SHA256_CHECK := shasum -a 256 --check
else
  SHA256_CMD := sha256sum
  SHA256_CHECK := sha256sum --check
endif

.PHONY: checksum verify clean release

# Generate SHA-256 checksum file for the smart-ssh script
checksum:
	$(SHA256_CMD) smart-ssh > smart-ssh.sha256
	@echo "Checksum written to smart-ssh.sha256"

# Verify the smart-ssh script against its checksum file
verify:
	$(SHA256_CHECK) smart-ssh.sha256

# Remove generated files
clean:
	rm -f smart-ssh.sha256 smart-ssh.sha256.asc

# Generate checksum file for release
# GPG signing must be done manually after this step:
#   gpg --detach-sign --armor smart-ssh.sha256
release: checksum
	@echo "Checksum for v$(VERSION) generated: smart-ssh.sha256"
	@echo "To sign for release, run:"
	@echo "  gpg --detach-sign --armor smart-ssh.sha256"
