# Coreutilz Makefile
# A Zig implementation of GNU Coreutils

# Variables
ZIG := zig
BUILD_DIR := zig-out
BIN_DIR := $(BUILD_DIR)/bin
COMMANDS := true false echo cat hostname logname tty whoami nproc hostid \
            unlink dirname basename printenv pwd readlink mkdir rmdir rm \
            link yes sleep sync env cp mv chmod ln stat dd head wc tee truncate touch cut paste

# Default target
.PHONY: all
all: build

# Build all commands
.PHONY: build
build:
	$(ZIG) build

# Build a specific command
.PHONY: $(COMMANDS)
$(COMMANDS):
	$(ZIG) build $@

# Run all tests
.PHONY: test
test:
	$(ZIG) build test

# Run tests with verbose output
.PHONY: test-verbose
test-verbose:
	$(ZIG) build test --verbose

# Run a specific test file
.PHONY: test-%
test-%:
	$(ZIG) test --dep framework -Mroot=tests/$*_test.zig -Mframework=tests/framework.zig

# Format all source files
.PHONY: fmt
fmt:
	$(ZIG) fmt src/ tests/

# Check formatting without modifying files
.PHONY: fmt-check
fmt-check:
	$(ZIG) fmt --check src/ tests/

# Clean build artifacts
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR) .zig-cache

# Install binaries to system
.PHONY: install
install: build
	install -d $(DESTDIR)/usr/bin
	for cmd in $(COMMANDS); do \
		install -m 755 $(BIN_DIR)/$$cmd $(DESTDIR)/usr/bin/; \
	done
	install -m 755 $(BIN_DIR)/coreutilz $(DESTDIR)/usr/bin/

# Uninstall binaries
.PHONY: uninstall
uninstall:
	for cmd in $(COMMANDS); do \
		rm -f $(DESTDIR)/usr/bin/$$cmd; \
	done
	rm -f $(DESTDIR)/usr/bin/coreutilz

# Run linter (ameba for Zig if available)
.PHONY: lint
lint:
	@echo "Running Zig format check..."
	$(ZIG) fmt --check src/ tests/

# Documentation
.PHONY: docs
docs:
	@echo "Documentation is in docs/ directory"
	@ls -la docs/

# Show help
.PHONY: help
help:
	@echo "Coreutilz - A Zig implementation of GNU Coreutils"
	@echo ""
	@echo "Available targets:"
	@echo "  all          - Build all commands (default)"
	@echo "  build        - Build all commands"
	@echo "  test         - Run all tests"
	@echo "  test-verbose - Run tests with verbose output"
	@echo "  test-<cmd>   - Run tests for specific command (e.g., test-cat)"
	@echo "  fmt          - Format all source files"
	@echo "  fmt-check    - Check formatting without modifying files"
	@echo "  clean        - Remove build artifacts"
	@echo "  install      - Install binaries to system"
	@echo "  uninstall    - Remove installed binaries"
	@echo "  lint         - Run code checks"
	@echo "  docs         - Show documentation"
	@echo "  help         - Show this help message"
	@echo ""
	@echo "Individual commands that can be built:"
	@echo "  $(COMMANDS)"

# Print version
.PHONY: version
version:
	@echo "Coreutilz version 0.1.0"
	@$(ZIG) version
