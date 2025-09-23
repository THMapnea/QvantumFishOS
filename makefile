# Makefile for NBOS Operating System
# ==================================
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

# Configuration
ASM=nasm
SRC_DIR=src
BUILD_DIR=build
CC=gcc
TOOLS_DIR=tools

# Phony targets
.PHONY: all floppy_image kernel bootloader clean always tools_fat

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
# 3. Writes bootloader to boot sector (sector 0)
# 4. Copies kernel as file to filesystem using mcopy
# 5. Copies test.txt file for testing purposes
#
# the kernel is loaded as "kernel.bin" file
# in the FAT12 filesystem instead of being written directly to disk sectors.

floppy_image: $(BUILD_DIR)/main_floppy.img

$(BUILD_DIR)/main_floppy.img: bootloader kernel
	dd if=/dev/zero of=$(BUILD_DIR)/main_floppy.img bs=512 count=2880
	sudo mkfs.fat -F 12 -n "NBOS" $(BUILD_DIR)/main_floppy.img
	sudo chown $(USER):$(USER) $(BUILD_DIR)/main_floppy.img
	dd if=$(BUILD_DIR)/bootloader.bin of=$(BUILD_DIR)/main_floppy.img conv=notrunc
	mcopy -i $(BUILD_DIR)/main_floppy.img $(BUILD_DIR)/kernel.bin "::kernel.bin"
	mcopy -i $(BUILD_DIR)/main_floppy.img test.txt"::test.txt"



# =============================================================================
# BOOTLOADER COMPILATION
# =============================================================================
#
# Compiles the bootloader from assembly code.
# The bootloader must be exactly 512 bytes (size of one sector)
# and is placed in the boot sector of the floppy disk.
#
# The bootloader in this version must be able to:
# 1. Load itself into memory
# 2. Find the "kernel.bin" file in the FAT12 filesystem
# 3. Load the kernel into memory
# 4. Transfer execution to the kernel

bootloader: $(BUILD_DIR)/bootloader.bin

$(BUILD_DIR)/bootloader.bin: always
	$(ASM) $(SRC_DIR)/bootloader/boot.asm -f bin -o $(BUILD_DIR)/bootloader.bin



# =============================================================================
# KERNEL COMPILATION
# =============================================================================
#
# Compiles the kernel from assembly code.
# the kernel is copied as a file to the FAT12 filesystem
# instead of being written directly to disk sectors.
#
# This approach allows:
# - Greater flexibility in kernel placement
# - Possibility to have multiple files in the filesystem
# - Better compatibility with standard tools

kernel: $(BUILD_DIR)/kernel.bin

$(BUILD_DIR)/kernel.bin: always
	$(ASM) $(SRC_DIR)/kernel/main.asm -f bin -o $(BUILD_DIR)/kernel.bin



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

tools_fat: $(BUILD_DIR)/tools/fat

$(BUILD_DIR)/tools/fat: always $(TOOLS_DIR)/fat/fat.c
	mkdir -p $(BUILD_DIR)/tools
	$(CC) -g -o $(BUILD_DIR)/tools/fat $(TOOLS_DIR)/fat/fat.c



# =============================================================================
# AUXILIARY TARGETS
# =============================================================================

# Target 'always': ensures build directory always exists
# This target runs before any compilation to guarantee the build
# directory structure is in place for output files

always:
	mkdir -p $(BUILD_DIR)

# Target 'clean': removes all compiled files
# Cleans the build directory to ensure a fresh build on next compilation
# Useful for troubleshooting build issues or preparing for distribution

clean:
	rm -rf $(BUILD_DIR)/*