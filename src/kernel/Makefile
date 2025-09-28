# =============================================================================
# NBOS KERNEL BUILD SYSTEM
# =============================================================================
#
# Makefile for building the NBOS kernel from assembly source
# Handles compilation of kernel binary and provides clean target

# =============================================================================
# BUILD CONFIGURATION
# =============================================================================

BUILD_DIR?=build/          # Directory where build outputs are stored (default: build/)
ASM?=nasm                  # Assembler to use (default: nasm)

# =============================================================================
# PHONY TARGET DECLARATIONS
# =============================================================================

.phony: all kernel clean    # Declare phony targets (not actual files)

# =============================================================================
# BUILD TARGETS
# =============================================================================

# Primary build target - builds kernel binary
all: kernel

# Target for building kernel binary
kernel: $(BUILD_DIR)/kernel.bin

# Rule to assemble main.asm into kernel.bin
# Uses NASM assembler to create raw binary output
$(BUILD_DIR)/kernel.bin:
	$(ASM) main.asm -f bin -o $(BUILD_DIR)/kernel.bin  # Assemble main.asm to binary format

# =============================================================================
# CLEANUP TARGET
# =============================================================================

# Clean target - removes all build artifacts
clean:
	rm -f $(BUILD_DIR)/kernel.bin  # Delete the kernel binary