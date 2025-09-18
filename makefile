ASM=nasm
SRC_DIR=src
BUILD_DIR=build



.PHONY: all floppy_image kernel bootloader clean always


#
#	FLOPPY IMAGE
#
floppy_image: $(BUILD_DIR)/main_floppy.img
$(BUILD_DIR)/main_floppy.img: bootloader kernel
	cp $(BUILD_DIR)/main.bin $(BUILD_DIR)/main_floppy.img
	truncate -s 1440k $(BUILD_DIR)/main_floppy.img



#
#	BOOTLOADER
#
bootloader: $(BUILD_DIR)/bootloader.bin
$(BUILD_DIR)/bootloader.bin: always
	$(ASM) $(SRC_DIR)/bootloader/bootloader.asm -f bin -o $(BUILD_DIR)/bootloader.bin



#
#	KERNEL
#
kernel: $(BUILD_DIR)/kernel.bin
$(BUILD_DIR)/kernel.bin: always
	$(ASM) $(SRC_DIR)/kernel/main.asm -f bin -o $(BUILD_DIR)/main.bin



#
#	ALWAYS
#
always:
	mkdir -p $(BUILD_DIR)


#
#	CLEAN
#
clean:
	rm -rf $(BUILD_DIR)/*
