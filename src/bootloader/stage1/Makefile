# =============================================================================
# NBOS BOOTLOADER BUILD SYSTEM
# =============================================================================
#
# Makefile for building the NBOS bootloader from assembly source
# Handles compilation of boot sector and provides clean target

# =============================================================================
# BUILD CONFIGURATION
# =============================================================================

BUILD_DIR?=build/          # Directory where build outputs are stored (default: build/)
ASM?=nasm                  # Assembler to use (default: nasm)

# =============================================================================
# PHONY TARGET DECLARATIONS
# =============================================================================

.phony all clean           # Declare phony targets (not actual files)

# =============================================================================
# BUILD TARGETS
# =============================================================================

# Primary build target - builds stage1 bootloader
all: stage1

# Target for building stage1 bootloader binary
stage1: $(BUILD_DIR)/stage1.bin

# Rule to assemble boot.asm into stage1.bin
# Uses NASM assembler to create raw binary output
$(BUILD_DIR)/stage1.bin:
	$(ASM) boot.asm -f bin -o $(BUILD_DIR)/stage1.bin  # Assemble boot.asm to binary format

# =============================================================================
# CLEANUP TARGET
# =============================================================================

# Clean target - removes all build artifacts
clean:
	rm -f $(BUILD_DIR)/stage1.bin  # Delete the stage1 bootloader binary