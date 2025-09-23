#include<stdio.h>
#include<stdint.h>
#include<stdlib.h>
#include<string.h>
#include<ctype.h>

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
// - Reads and displays file contents
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

// =============================================================================
// DIRECTORY ENTRY STRUCTURE
// =============================================================================
//
// Represents a directory entry in the FAT12 filesystem.
// Each entry contains metadata about a file or subdirectory including
// name, attributes, timestamps, cluster information, and file size.
//
// Attributes:
// - Name:                 File name (8.3 format - 8 characters name, 3 characters extension)
// - Attributes:           File attributes (read-only, hidden, system, etc.)
// - _reserved:            Reserved byte for alignment
// - CreatedTimeTenths:    Tenths of seconds for creation time
// - CreatedTime:          File creation time (hours, minutes, seconds)
// - CreatedDate:          File creation date (year, month, day)
// - AccessDate:           Last access date
// - FirstClusterHigh:     High 16 bits of first cluster number (usually 0 in FAT12)
// - FirstClusterLow:      Low 16 bits of first cluster number
// - ModifiedTime:         Last modification time
// - ModifiedDate:         Last modification date
// - Size:                 File size in bytes

typedef struct{
    uint8_t Name[11];              // File name in 8.3 format (no dot)
    uint8_t Attributes;            // File attributes
    uint8_t _reserved;             // Reserved for future use
    uint8_t CreatedTimeTenths;     // Tenths of seconds (0-199)
    uint16_t CreatedTime;          // Creation time (hour:minute:second)
    uint16_t CreatedDate;          // Creation date (year:month:day)
    uint16_t AccessDate;           // Last access date
    uint16_t FirstClusterHigh;     // High word of first cluster (FAT32)
    uint16_t FirstClusterLow;      // Low word of first cluster
    uint16_t ModifiedTime;         // Last modification time
    uint16_t ModifiedDate;         // Last modification date
    uint32_t Size;                 // File size in bytes

}__attribute__((packed)) DirectoryEntry;

// Global variables for boot sector and FAT table
BootSector g_BootSector;           // Stores the boot sector information
uint8_t* g_Fat = NULL;             // Pointer to FAT table data
DirectoryEntry* g_RootDirectory = NULL;  // Pointer to root directory entries
uint32_t g_RootDirectoryEnd;       // LBA of the first sector after root directory

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
// ROOT DIRECTORY READING FUNCTION
// =============================================================================
//
// Reads the root directory from the disk image.
// The root directory is located after the FAT tables and contains
// entries for all files and directories in the root of the filesystem.
//
// Parameters:
// - disk: FILE pointer to the open disk image
//
// Returns:
// - true:  Root directory read successfully
// - false: Failed to read root directory

bool readRootDirectory(FILE* disk){
    // Calculate LBA of root directory (after reserved sectors and all FAT copies)
    uint32_t lba = g_BootSector.ReservedSectors + g_BootSector.SectorsPerFat * g_BootSector.FatCount;
    // Calculate total size needed for root directory entries
    uint32_t size = sizeof(DirectoryEntry) * g_BootSector.DirEntryCount;
    // Calculate number of sectors needed (rounding up if necessary)
    uint32_t sectors = (size / g_BootSector.BytesPerSector);

    // If directory size doesn't align perfectly with sector boundary, add extra sector
    if(size % g_BootSector.BytesPerSector > 0){
        sectors++;
    }
    
    // Store the LBA of the first sector after root directory (where data area begins)
    g_RootDirectoryEnd = lba + sectors;
    // Allocate memory for root directory (sector-aligned)
    g_RootDirectory = (DirectoryEntry*) malloc(sectors * g_BootSector.BytesPerSector);
    // Read root directory sectors from disk
    return readSectors(disk, lba, sectors, g_RootDirectory);
}

// =============================================================================
// FILE SEARCH FUNCTION
// =============================================================================
//
// Searches for a file by name in the root directory.
// Compares the provided filename with directory entries using exact 8.3 format matching.
//
// Parameters:
// - name: Filename to search for (must be in 8.3 format without dot)
//
// Returns:
// - Pointer to DirectoryEntry if file found
// - NULL if file not found

DirectoryEntry* findFile(const char* name){
    // Iterate through all root directory entries
    for(uint32_t i = 0; i < g_BootSector.DirEntryCount; i++){
        // Compare filename (exact match of 11 characters in 8.3 format)
        if(memcmp(name, g_RootDirectory[i].Name, 11) == 0){
            return &g_RootDirectory[i];  // Return pointer to matching entry
        }
    }

    return NULL;  // File not found
}

// =============================================================================
// FILE READING FUNCTION
// =============================================================================
//
// Reads the contents of a file from the disk image by following the cluster chain
// in the FAT table. Files are stored in clusters that may be non-contiguous,
// requiring traversal of the FAT to locate all clusters belonging to the file.
//
// Parameters:
// - fileEntry:    Pointer to the directory entry of the file to read
// - disk:         FILE pointer to the open disk image
// - outputBuffer: Buffer to store the file contents (must be large enough for file size)
//
// Returns:
// - true:  File read successfully
// - false: Failed to read file

bool readFile(DirectoryEntry* fileEntry, FILE* disk, uint8_t* outputBuffer){
    bool loop = true;
    // Start with the first cluster of the file
    uint16_t currentCluster = fileEntry->FirstClusterLow;

    // Follow the cluster chain until end-of-file marker is reached
    do{
        // Calculate LBA of current cluster (data area starts after root directory)
        uint32_t lba = g_RootDirectoryEnd + (currentCluster - 2) * g_BootSector.SectorsPerCluster;
        // Read the current cluster
        loop = loop && readSectors(disk, lba, g_BootSector.SectorsPerCluster, outputBuffer);
        // Advance output buffer pointer by cluster size
        outputBuffer += g_BootSector.SectorsPerCluster * g_BootSector.BytesPerSector;

        // Calculate FAT index for current cluster (FAT12 uses 12-bit entries)
        uint32_t fatIndex = currentCluster * 3 / 2;
        
        // Read next cluster from FAT (handles 12-bit entries)
        if(currentCluster % 2 == 0){
            // Even cluster: use low 12 bits of 16-bit value
            currentCluster = (*(uint16_t*)(g_Fat + fatIndex)) & 0x0FFF;
        }else{
            // Odd cluster: use high 12 bits of 16-bit value
            currentCluster = (*(uint16_t*)(g_Fat + fatIndex)) >> 4;
        }

    // Continue until end-of-file cluster (0xFF8-0xFFF) is reached
    }while(loop && currentCluster < 0xFF8);
    
    return loop;
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
// 5. Read root directory
// 6. Search for specified file
// 7. Read file contents
// 8. Display file contents
// 9. Clean up resources
//
// Return codes:
// - 0:  Success
// - -1: Invalid arguments or cannot open disk
// - -2: Boot sector read error
// - -3: FAT read error
// - -4: Root directory read error
// - -5: File not found error
// - -6: File read error

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
    
    // Read root directory from disk image
    if(!readRootDirectory(disk)){
        fprintf(stderr, "could not read root!\n");
        free(g_Fat);
        free(g_RootDirectory);
        return -4;
    }

    // Search for the specified file in root directory
    DirectoryEntry* fileEntry = findFile(argv[2]);

    // Check if file was found
    if(!fileEntry){
        fprintf(stderr, "could not find file! %s!\n", argv[2]);
        free(g_Fat);
        free(g_RootDirectory);
        return -5;
    }

    // Allocate buffer for file contents (with extra sector for safety)
    uint8_t* buffer = (uint8_t*) malloc(fileEntry->Size + g_BootSector.BytesPerSector);
    
    // Read file contents from disk
    if(!readFile(fileEntry, disk, buffer)){
        fprintf(stderr, "could not read the file! %s!\n", argv[2]);
        free(buffer);
        free(g_Fat);
        free(g_RootDirectory);
        return -6;
    }

    // Display file contents with printable character filtering
    for(size_t i = 0; i < fileEntry->Size; i++){
        if(isprint(buffer[i])) 
            fputc(buffer[i], stdout);  // Print printable characters directly
        else 
            printf("<%02x", buffer[i]);  // Show hex codes for non-printable characters
    }
    printf("\n");

    // Clean up allocated memory
    free(buffer);
    free(g_Fat);
    free(g_RootDirectory);
    return 0;
}