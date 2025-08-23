# Glo55 Tiling Window Manager Makefile

# Variables
V = v
BINARY = glo55
DIST_DIR = dist
BINARY_PATH = $(DIST_DIR)/$(BINARY)

# Default target
all: build

# Create dist directory if it doesn't exist
$(DIST_DIR):
	mkdir -p $(DIST_DIR)

# Build the main executable in dist/
build: $(DIST_DIR)
	$(V) -o $(BINARY_PATH) .

# Build and run from dist/
run: build
	./$(BINARY_PATH)

# Run tests
test:
	$(V) run tests/core_test.v

# Format all V files
fmt:
	$(V) fmt -w .

# Check compilation without building
check:
	$(V) -check .

# Lint (format verification and compile check)
lint:
	$(V) fmt -verify .
	$(V) -check .

# Development workflow
dev: fmt check run

# Clean build artifacts (including dist folder)
clean:
	rm -rf $(DIST_DIR)
	rm -f *.tmp

# Help target
help:
	@echo "Available targets:"
	@echo "  all      - Build the project (default)"
	@echo "  build    - Compile executable to dist/glo55"
	@echo "  run      - Build and run from dist/"
	@echo "  test     - Run the test suite"
	@echo "  fmt      - Format all V source files"
	@echo "  check    - Run compiler checks"
	@echo "  lint     - Verify formatting and run checks"
	@echo "  dev      - Development workflow (fmt + check + run)"
	@echo "  clean    - Remove dist/ and build artifacts"
	@echo "  help     - Show this help message"

.PHONY: all build run test fmt check lint dev clean help