# =============================================================================
# NBOS BOOTLOADER STAGE2 BUILD SYSTEM
# =============================================================================
#
# Makefile for building the NBOS stage2 bootloader from assembly source
# Handles compilation of stage2 bootloader and provides clean target

# =============================================================================
# BUILD CONFIGURATION
# =============================================================================

BUILD_DIR?=build/          # Directory where build outputs are stored (default: build/)
ASM?=nasm                  # Assembler to use (default: nasm)

# =============================================================================
# PHONY TARGET DECLARATIONS
# =============================================================================

.phony: all clean           # Declare phony targets (not actual files)

# =============================================================================
# BUILD TARGETS
# =============================================================================

# Primary build target - builds stage2 bootloader
all: stage2

# Target for building stage2 bootloader binary
stage2: $(BUILD_DIR)/stage2.bin

# Rule to assemble main.asm into stage2.bin
# Uses NASM assembler to create raw binary output
$(BUILD_DIR)/stage2.bin:
	$(ASM) main.asm -f bin -o $(BUILD_DIR)/stage2.bin  # Assemble main.asm to binary format

# =============================================================================
# CLEANUP TARGET
# =============================================================================

# Clean target - removes all build artifacts
clean:
	rm -f $(BUILD_DIR)/stage2.bin  # Delete the stage2 bootloader binary