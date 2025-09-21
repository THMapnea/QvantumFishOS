#include<stdio.h>
#include<stdint.h>
#include<stdlib.h>

// =============================================================================
// FAT12 FILESYSTEM ANALYSIS TOOL
// =============================================================================
//
// This tool analyzes FAT12 filesystem structures on a disk image.
// It reads the boot sector and FAT (File Allocation Table) to provide
// information about the filesystem layout and structure.
//
// Usage: fat <disk image> <file name>
//
// Features:
// - Reads and parses boot sector information
// - Loads and analyzes FAT table
// - Provides foundation for file operations on FAT12 filesystem

// Boolean type definition for better code readability
typedef uint8_t bool;
#define true 1
#define false 0

// =============================================================================
// BOOT SECTOR STRUCTURE
// =============================================================================
//
// Represents the boot sector of a FAT12 filesystem.
// The boot sector contains critical information about the filesystem layout
// including sector sizes, cluster information, and filesystem geometry.
//
// Attributes:
// - BootJumpInstruction:  Jump instruction to boot code (3 bytes)
// - OEMIdentifier:        Original Equipment Manufacturer identifier (8 bytes)
// - BytesPerSector:       Number of bytes per sector (typically 512)
// - SectorsPerCluster:    Number of sectors per allocation unit
// - ReservedSectors:      Number of reserved sectors (including boot sector)
// - FatCount:             Number of FAT tables (typically 2 for redundancy)
// - DirEntryCount:        Number of root directory entries
// - TotalSector:          Total number of sectors (if ≤ 65535)
// - MediaDescriptorType:  Storage medium type identifier
// - SectorsPerFat:        Number of sectors per FAT table
// - SectorsPertrack:      Sectors per track (for disk geometry)
// - Heads:                Number of read/write heads (for disk geometry)
// - HiddenSectors:        Number of hidden sectors
// - LargeSectorCount:     Total sectors if > 65535
// - DriveNumber:          BIOS drive number
// - _Reserved:            Reserved byte
// - Signature:            Extended boot signature
// - VolumeId:             Volume serial number
// - VolumeLabel:          Volume label (11 characters)
// - SystemId:             Filesystem type identifier (8 characters)

typedef struct{
    uint8_t BootJumpInstruction[3];        // Jump to boot code (EB 3C 90)
    uint8_t OEMIdentifier[8];              // OEM name/version
    uint16_t BytesPerSector;               // Bytes per sector (usually 512)
    uint8_t SectorsPerCluster;             // Sectors per cluster
    uint16_t ReservedSectors;              // Reserved sectors count
    uint8_t FatCount;                      // Number of FAT tables
    uint16_t DirEntryCount;                // Root directory entries
    uint16_t TotalSector;                  // Total sectors (if small)
    uint8_t MediaDescriptorType;           // Media descriptor
    uint16_t SectorsPerFat;                // Sectors per FAT
    uint16_t SectorsPertrack;              // Sectors per track
    uint16_t Heads;                        // Number of heads
    uint32_t HiddenSectors;                // Hidden sectors
    uint32_t LargeSectorCount;             // Large sector count

    uint8_t DriveNumber;                   // Drive number (0x00=floppy, 0x80=HDD)
    uint8_t _Reserved;                     // Reserved (used by Windows NT)
    uint8_t Signature;                     // Signature (should be 0x28 or 0x29)
    uint32_t VolumeId;                     // Volume serial number
    uint8_t VolumeLabel[11];               // Volume label
    uint8_t SystemId[8];                   // Filesystem type (e.g., "FAT12   ")

}__attribute__((packed)) BootSector;

// Global variables for boot sector and FAT table
BootSector g_BootSector;   // Stores the boot sector information
uint8_t* g_Fat = NULL;     // Pointer to FAT table data

// =============================================================================
// BOOT SECTOR READING FUNCTION
// =============================================================================
//
// Reads the boot sector from the disk image file.
//
// Parameters:
// - disk: FILE pointer to the open disk image
//
// Returns:
// - true:  Boot sector read successfully
// - false: Failed to read boot sector

bool readBootSector(FILE* disk){
    return fread(&g_BootSector, sizeof(g_BootSector), 1, disk) > 0;
}

// =============================================================================
// SECTOR READING FUNCTION
// =============================================================================
//
// Reads one or more sectors from the disk image starting at the specified LBA.
//
// Parameters:
// - disk:        FILE pointer to the open disk image
// - lba:         Logical Block Address (sector number) to start reading from
// - count:       Number of sectors to read
// - bufferOut:   Output buffer for the read data
//
// Returns:
// - true:  Sectors read successfully
// - false: Failed to read sectors

bool readSectors(FILE* disk, uint32_t lba, uint32_t count, void* bufferOut){
    bool ok = true;
    // Seek to the starting sector
    ok = ok && (fseek(disk, lba * g_BootSector.BytesPerSector, SEEK_SET) == 0);
    // Read the specified number of sectors
    ok = ok && (fread(bufferOut, g_BootSector.BytesPerSector, count, disk) == count);
    return ok;
}

// =============================================================================
// FAT TABLE READING FUNCTION
// =============================================================================
//
// Reads the File Allocation Table from the disk image.
// The FAT is located after the reserved sectors and contains information
// about which clusters are allocated, free, or bad.
//
// Parameters:
// - disk: FILE pointer to the open disk image
//
// Returns:
// - true:  FAT read successfully
// - false: Failed to read FAT

bool readFat(FILE* disk){
    // Allocate memory for FAT table (size = sectors per FAT × bytes per sector)
    g_Fat = (uint8_t*) malloc(g_BootSector.SectorsPerFat * g_BootSector.BytesPerSector);
    // Read FAT table starting after reserved sectors
    return readSectors(disk, g_BootSector.ReservedSectors, g_BootSector.SectorsPerFat, g_Fat);
}

// =============================================================================
// MAIN FUNCTION
// =============================================================================
//
// Entry point of the FAT analysis tool.
// Handles command line arguments, file operations, and error checking.
//
// Command line syntax:
//   fat <disk image> <file name>
//
// Workflow:
// 1. Check command line arguments
// 2. Open disk image file
// 3. Read boot sector information
// 4. Read FAT table
// 5. Clean up resources
//
// Return codes:
// - 0:  Success
// - -1: Invalid arguments
// - -2: Boot sector read error
// - -3: FAT read error

int main(int argc, char** argv){

    // Check for correct number of command line arguments
    if(argc < 3){
        printf("Syntax: %s <disk image> <file name>\n", argv[0]);
        return -1;
    }

    // Open the disk image file for reading
    FILE* disk = fopen(argv[1], "rb");

    // Check if file opened successfully
    if(!disk){
        fprintf(stderr, "cannot open disk image %s!", argv[1]);
        return -1;
    }

    // Read boot sector from disk image
    if(!readBootSector(disk)){
        fprintf(stderr, "could not read boot sector! %s\n");
        return -2;
    }

    // Read FAT table from disk image
    if(!readFat(disk)){
        fprintf(stderr, "could not read FAT!\n");
        free(g_Fat);
        return -3;
    }

    // Clean up allocated memory
    free(g_Fat);

    return 0;
}