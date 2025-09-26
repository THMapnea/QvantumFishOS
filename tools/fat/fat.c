// =============================================================================
// FAT12 FILESYSTEM READER
// =============================================================================
//
// This program reads and extracts files from a FAT12 disk image
// It can display the contents of text files found in the root directory

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

// =============================================================================
// TYPE DEFINITIONS
// =============================================================================

// Boolean type definition for C (since C doesn't have built-in bool type in older standards)
typedef uint8_t bool;
#define true 1
#define false 0

// Boot Sector structure - represents the first sector of a FAT12 filesystem
typedef struct 
{
    uint8_t BootJumpInstruction[3];    // Jump instruction to boot code
    uint8_t OemIdentifier[8];          // OEM name/identifier
    uint16_t BytesPerSector;           // Bytes per sector (usually 512)
    uint8_t SectorsPerCluster;         // Sectors per cluster
    uint16_t ReservedSectors;          // Number of reserved sectors
    uint8_t FatCount;                  // Number of FAT tables (usually 2)
    uint16_t DirEntryCount;            // Number of root directory entries
    uint16_t TotalSectors;             // Total sectors in filesystem
    uint8_t MediaDescriptorType;       // Media descriptor type
    uint16_t SectorsPerFat;            // Sectors per FAT table
    uint16_t SectorsPerTrack;          // Sectors per track
    uint16_t Heads;                    // Number of heads
    uint32_t HiddenSectors;            // Number of hidden sectors
    uint32_t LargeSectorCount;         // Large sector count (if TotalSectors is 0)

    // Extended boot record fields
    uint8_t DriveNumber;               // Drive number
    uint8_t _Reserved;                 // Reserved byte
    uint8_t Signature;                 // Extended boot signature
    uint32_t VolumeId;                 // Volume serial number
    uint8_t VolumeLabel[11];           // Volume label (11 bytes, padded with spaces)
    uint8_t SystemId[8];               // Filesystem type identifier

} __attribute__((packed)) BootSector;

// Directory Entry structure - represents a file or directory entry in FAT12
typedef struct 
{
    uint8_t Name[11];                  // 8.3 filename (8 name + 3 extension)
    uint8_t Attributes;                // File attributes (read-only, hidden, etc.)
    uint8_t _Reserved;                 // Reserved byte
    uint8_t CreatedTimeTenths;         // Created time tenths of seconds
    uint16_t CreatedTime;              // Created time
    uint16_t CreatedDate;              // Created date
    uint16_t AccessedDate;             // Last accessed date
    uint16_t FirstClusterHigh;         // High word of first cluster number (usually 0 in FAT12)
    uint16_t ModifiedTime;             // Last modified time
    uint16_t ModifiedDate;             // Last modified date
    uint16_t FirstClusterLow;          // Low word of first cluster number
    uint32_t Size;                     // File size in bytes

} __attribute__((packed)) DirectoryEntry;

// =============================================================================
// GLOBAL VARIABLES
// =============================================================================

BootSector g_BootSector;               // Stores the boot sector data
uint8_t* g_Fat = NULL;                 // Pointer to FAT table in memory
DirectoryEntry* g_RootDirectory = NULL; // Pointer to root directory in memory
uint32_t g_RootDirectoryEnd;           // LBA address where root directory ends

// =============================================================================
// DISK READING FUNCTIONS
// =============================================================================

// Reads the boot sector from the disk image
// Parameters:
//   disk - FILE pointer to the disk image
// Returns: true if successful, false otherwise
bool readBootSector(FILE* disk)
{
    return fread(&g_BootSector, sizeof(g_BootSector), 1, disk) > 0;
}

// Reads one or more sectors from the disk image
// Parameters:
//   disk - FILE pointer to the disk image
//   lba - Logical Block Address (sector number) to start reading from
//   count - Number of sectors to read
//   bufferOut - Pointer to buffer where data will be stored
// Returns: true if successful, false otherwise
bool readSectors(FILE* disk, uint32_t lba, uint32_t count, void* bufferOut)
{
    bool ok = true;
    // Seek to the correct position in the disk image
    ok = ok && (fseek(disk, lba * g_BootSector.BytesPerSector, SEEK_SET) == 0);
    // Read the specified number of sectors
    ok = ok && (fread(bufferOut, g_BootSector.BytesPerSector, count, disk) == count);
    return ok;
}

// Reads the FAT (File Allocation Table) from the disk image
// Parameters:
//   disk - FILE pointer to the disk image
// Returns: true if successful, false otherwise
bool readFat(FILE* disk)
{
    // Allocate memory for the FAT table
    g_Fat = (uint8_t*) malloc(g_BootSector.SectorsPerFat * g_BootSector.BytesPerSector);
    // Read FAT from disk (located after reserved sectors)
    return readSectors(disk, g_BootSector.ReservedSectors, g_BootSector.SectorsPerFat, g_Fat);
}

// Reads the root directory from the disk image
// Parameters:
//   disk - FILE pointer to the disk image
// Returns: true if successful, false otherwise
bool readRootDirectory(FILE* disk)
{
    // Calculate LBA address of root directory (after reserved sectors and FAT tables)
    uint32_t lba = g_BootSector.ReservedSectors + g_BootSector.SectorsPerFat * g_BootSector.FatCount;
    // Calculate size of root directory in bytes
    uint32_t size = sizeof(DirectoryEntry) * g_BootSector.DirEntryCount;
    // Calculate how many sectors the root directory occupies
    uint32_t sectors = (size / g_BootSector.BytesPerSector);
    if (size % g_BootSector.BytesPerSector > 0)
        sectors++;

    // Store the end position of root directory for later calculations
    g_RootDirectoryEnd = lba + sectors;
    // Allocate memory for root directory
    g_RootDirectory = (DirectoryEntry*) malloc(sectors * g_BootSector.BytesPerSector);
    // Read root directory from disk
    return readSectors(disk, lba, sectors, g_RootDirectory);
}

// =============================================================================
// FILE OPERATION FUNCTIONS
// =============================================================================

// Searches for a file in the root directory by name
// Parameters:
//   name - 11-character filename in 8.3 format (without dot)
// Returns: Pointer to directory entry if found, NULL otherwise
DirectoryEntry* findFile(const char* name)
{
    // Iterate through all root directory entries
    for (uint32_t i = 0; i < g_BootSector.DirEntryCount; i++)
    {
        // Compare filename with directory entry name
        if (memcmp(name, g_RootDirectory[i].Name, 11) == 0)
            return &g_RootDirectory[i];  // Return pointer to matching entry
    }

    return NULL;  // File not found
}

// Reads a file from the disk image into memory
// Parameters:
//   fileEntry - Pointer to the file's directory entry
//   disk - FILE pointer to the disk image
//   outputBuffer - Pointer to buffer where file content will be stored
// Returns: true if successful, false otherwise
bool readFile(DirectoryEntry* fileEntry, FILE* disk, uint8_t* outputBuffer)
{
    bool ok = true;
    // Start with the file's first cluster
    uint16_t currentCluster = fileEntry->FirstClusterLow;

    // Follow cluster chain until end of file marker (0x0FF8 or higher)
    do {
        // Calculate LBA address of current cluster
        // Formula: RootDirectoryEnd + (cluster - 2) * sectors per cluster
        // (cluster numbers start at 2, with 0 and 1 being special values)
        uint32_t lba = g_RootDirectoryEnd + (currentCluster - 2) * g_BootSector.SectorsPerCluster;
        // Read the cluster into output buffer
        ok = ok && readSectors(disk, lba, g_BootSector.SectorsPerCluster, outputBuffer);
        // Advance output buffer pointer by cluster size
        outputBuffer += g_BootSector.SectorsPerCluster * g_BootSector.BytesPerSector;

        // Calculate index in FAT for next cluster
        // FAT12 uses 12-bit entries, so we need special handling
        uint32_t fatIndex = currentCluster * 3 / 2;
        
        // Extract next cluster number from FAT (depends on whether cluster is even or odd)
        if (currentCluster % 2 == 0)
            // Even cluster: take lower 12 bits of 16-bit value
            currentCluster = (*(uint16_t*)(g_Fat + fatIndex)) & 0x0FFF;
        else
            // Odd cluster: take upper 12 bits of 16-bit value
            currentCluster = (*(uint16_t*)(g_Fat + fatIndex)) >> 4;

    } while (ok && currentCluster < 0x0FF8);  // Continue until end of file marker

    return ok;
}

// =============================================================================
// MAIN PROGRAM
// =============================================================================

int main(int argc, char** argv)
{
    // Check command line arguments
    if (argc < 3) {
        printf("Syntax: %s <disk image> <file name>\n", argv[0]);
        return -1;
    }

    // Open disk image file
    FILE* disk = fopen(argv[1], "rb");
    if (!disk) {
        fprintf(stderr, "Cannot open disk image %s!\n", argv[1]);
        return -1;
    }

    // Read boot sector (first step in reading FAT12 filesystem)
    if (!readBootSector(disk)) {
        fprintf(stderr, "Could not read boot sector!\n");
        return -2;
    }

    // Read FAT table
    if (!readFat(disk)) {
        fprintf(stderr, "Could not read FAT!\n");
        free(g_Fat);
        return -3;
    }

    // Read root directory
    if (!readRootDirectory(disk)) {
        fprintf(stderr, "Could not read FAT!\n");
        free(g_Fat);
        free(g_RootDirectory);
        return -4;
    }

    // Search for requested file in root directory
    DirectoryEntry* fileEntry = findFile(argv[2]);
    if (!fileEntry) {
        fprintf(stderr, "Could not find file %s!\n", argv[2]);
        free(g_Fat);
        free(g_RootDirectory);
        return -5;
    }

    // Allocate buffer for file content (with extra sector for safety)
    uint8_t* buffer = (uint8_t*) malloc(fileEntry->Size + g_BootSector.BytesPerSector);
    if (!readFile(fileEntry, disk, buffer)) {
        fprintf(stderr, "Could not read file %s!\n", argv[2]);
        free(g_Fat);
        free(g_RootDirectory);
        free(buffer);
        return -5;
    }

    // Display file content
    // Printable characters are shown as-is, non-printable as hex codes
    for (size_t i = 0; i < fileEntry->Size; i++)
    {
        if (isprint(buffer[i])) 
            fputc(buffer[i], stdout);  // Print printable characters
        else 
            printf("<%02x>", buffer[i]);  // Show hex code for non-printable
    }
    printf("\n");

    // Clean up allocated memory
    free(buffer);
    free(g_Fat);
    free(g_RootDirectory);
    
    return 0;
}