ASM=nasm
SRC_DIR=src
BUILD_DIR=build

.PHONY: all clean dirs

all: $(BUILD_DIR)/main_floppy.img

dirs:
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/main_floppy.img: $(BUILD_DIR)/main.bin | dirs
	cp $(BUILD_DIR)/main.bin $(BUILD_DIR)/main_floppy.img
	truncate -s 1440k $(BUILD_DIR)/main_floppy.img

$(BUILD_DIR)/main.bin: $(SRC_DIR)/main.asm | dirs
	$(ASM) $(SRC_DIR)/main.asm -f bin -o $(BUILD_DIR)/main.bin

clean:
	rm -rf $(BUILD_DIR)
