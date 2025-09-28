# =============================================================================
# NBOS OPERATING SYSTEM BUILD SYSTEM
# =============================================================================
#
# This Makefile automates the construction of a simple operating system
# composed of a bootloader and a kernel, producing a bootable floppy disk image.
#
# Project structure:
# - SRC_DIR=src:        Directory containing source files
# - BUILD_DIR=build:    Directory where compiled files are produced
# - ASM=nasm:           Assembler used (Netwide Assembler)
# - CC=gcc:             C compiler used for tools
# - TOOLS_DIR=tools:    Directory containing utility tools
#
# Available targets:
# - floppy_image:   Creates complete floppy disk image (main target)
# - bootloader:     Compiles only the bootloader
# - kernel:         Compiles only the kernel
# - tools_fat:      Compiles the FAT filesystem utility tool
# - clean:          Cleans the build directory

# =============================================================================
# BUILD CONFIGURATION
# =============================================================================

ASM=nasm                    # Assembler to use for assembly files (Netwide Assembler)
SRC_DIR=src                 # Root directory containing all source code
BUILD_DIR=build             # Directory where all build outputs are stored
CC=gcc                      # C compiler for compiling utility tools
TOOLS_DIR=tools             # Directory containing build utility programs

# =============================================================================
# PHONY TARGET DECLARATIONS
# =============================================================================

.PHONY: all floppy_image kernel bootloader clean always tools_fat

# =============================================================================
# PRIMARY BUILD TARGET
# =============================================================================

# Main target that builds everything: floppy image and tools
all: floppy_image tools_fat

# =============================================================================
# FLOPPY DISK IMAGE CREATION
# =============================================================================
#
# Main target: creates a complete bootable floppy disk image
# containing both bootloader and kernel.
#
# Workflow:
# 1. Creates empty 1.44MB image (2880 sectors of 512 bytes each)
# 2. Formats image as FAT12 filesystem with volume name "NBOS"
# 3. Writes stage1 bootloader to boot sector (sector 0)
# 4. Copies stage2 bootloader, kernel, and test file to filesystem using mcopy
#
# The stage2 bootloader and kernel are loaded as files in the FAT12 filesystem
# instead of being written directly to disk sectors.

floppy_image: $(BUILD_DIR)/main_floppy.img

$(BUILD_DIR)/main_floppy.img: bootloader kernel
	dd if=/dev/zero of=$(BUILD_DIR)/main_floppy.img bs=512 count=2880  # Create empty 1.44MB disk image
	sudo mkfs.fat -F 12 -n "NBOS" $(BUILD_DIR)/main_floppy.img         # Format as FAT12 with volume label "NBOS"
	sudo chown $(USER):$(USER) $(BUILD_DIR)/main_floppy.img            # Change ownership to current user
	dd if=$(BUILD_DIR)/stage1.bin of=$(BUILD_DIR)/main_floppy.img conv=notrunc  # Write stage1 bootloader to boot sector
	mcopy -i $(BUILD_DIR)/main_floppy.img $(BUILD_DIR)/stage2.bin "::stage2.bin"  # Copy stage2 bootloader to filesystem
	mcopy -i $(BUILD_DIR)/main_floppy.img $(BUILD_DIR)/kernel.bin "::kernel.bin"  # Copy kernel to filesystem
	mcopy -i $(BUILD_DIR)/main_floppy.img test.txt "::test.txt"                   # Copy test file to filesystem

# =============================================================================
# BOOTLOADER COMPILATION
# =============================================================================
#
# Compiles the bootloader from assembly code.
# The bootloader is split into two stages:
# - Stage1: 512-byte boot sector that loads stage2
# - Stage2: Secondary loader that loads the kernel
#
# The bootloader must be able to:
# 1. Load itself into memory (stage1)
# 2. Load stage2 from FAT12 filesystem
# 3. Find and load the "kernel.bin" file
# 4. Transfer execution to the kernel

bootloader: stage1 stage2

# Stage1 bootloader target - initial boot sector (512 bytes)
stage1: $(BUILD_DIR)/stage1.bin

$(BUILD_DIR)/stage1.bin: always
	$(MAKE) -C $(SRC_DIR)/bootloader/stage1 BUILD_DIR=$(abspath $(BUILD_DIR))  # Build stage1 in subdirectory

# Stage2 bootloader target - secondary loader
stage2: $(BUILD_DIR)/stage2.bin

$(BUILD_DIR)/stage2.bin: always
	$(MAKE) -C $(SRC_DIR)/bootloader/stage2 BUILD_DIR=$(abspath $(BUILD_DIR))  # Build stage2 in subdirectory

# =============================================================================
# KERNEL COMPILATION
# =============================================================================
#
# Compiles the kernel from assembly code.
# The kernel is copied as a file to the FAT12 filesystem
# instead of being written directly to disk sectors.
#
# This approach allows:
# - Greater flexibility in kernel placement and size
# - Possibility to have multiple files in the filesystem
# - Better compatibility with standard tools
# - Easier debugging and development

kernel: $(BUILD_DIR)/kernel.bin

$(BUILD_DIR)/kernel.bin: always
	$(MAKE) -C $(SRC_DIR)/kernel BUILD_DIR=$(abspath $(BUILD_DIR))  # Build kernel in subdirectory

# =============================================================================
# TOOLS COMPILATION
# =============================================================================
#
# Compiles utility tools needed for the operating system development.
# Currently includes a FAT filesystem utility for working with the
# FAT12 filesystem on the floppy disk image.
#
# The fat tool provides functionality for:
# - Reading and analyzing FAT12 filesystem structures
# - Debugging filesystem-related issues
# - Manipulating files on the disk image
# - Testing filesystem operations

tools_fat: $(BUILD_DIR)/tools/fat

$(BUILD_DIR)/tools/fat: always $(TOOLS_DIR)/fat/fat.c
	mkdir -p $(BUILD_DIR)/tools                     # Create tools directory if it doesn't exist
	$(CC) -g -o $(BUILD_DIR)/tools/fat $(TOOLS_DIR)/fat/fat.c  # Compile FAT utility with debug info

# =============================================================================
# AUXILIARY TARGETS
# =============================================================================

# Target 'always': ensures build directory always exists
# This target runs before any compilation to guarantee the build
# directory structure is in place for output files

always:
	mkdir -p $(BUILD_DIR)  # Create build directory if it doesn't exist

# =============================================================================
# CLEAN TARGET
# =============================================================================
#
# Target 'clean': removes all compiled files
# Cleans the build directory to ensure a fresh build on next compilation
# Useful for troubleshooting build issues or preparing for distribution
# Also cleans subdirectories by invoking their clean targets

clean:
	$(MAKE) -C $(SRC_DIR)/bootloader/stage1 BUILD_DIR=$(abspath $(BUILD_DIR)) clean  # Clean stage1 bootloader
	$(MAKE) -C $(SRC_DIR)/bootloader/stage2 BUILD_DIR=$(abspath $(BUILD_DIR)) clean  # Clean stage2 bootloader
	$(MAKE) -C $(SRC_DIR)/kernel BUILD_DIR=$(abspath $(BUILD_DIR)) clean             # Clean kernel
	rm -rf $(BUILD_DIR)/*                                                            # Remove all files from build directory