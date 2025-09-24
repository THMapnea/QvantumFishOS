#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

// =============================================================================
// CONSTANTS AND TYPE DEFINITIONS
// =============================================================================

typedef uint8_t bool;
#define true 1
#define false 0

// =============================================================================
// FAT12 BOOT SECTOR STRUCTURE
// =============================================================================
// Contains critical filesystem metadata including sector sizes, cluster 
// information, and disk geometry. All fields are packed to ensure proper
// alignment with on-disk structure.

typedef struct {
    // Boot code jump instruction (typically EB 3C 90)
    uint8_t BootJumpInstruction[3];
    
    // OEM name and version (8 bytes padded with spaces)
    uint8_t OEMIdentifier[8];
    
    // Fundamental filesystem parameters
    uint16_t BytesPerSector;       // Usually 512
    uint8_t SectorsPerCluster;     // Allocation unit size
    uint16_t ReservedSectors;      // Boot sector + reserved area
    uint8_t FatCount;              // Typically 2 for redundancy
    uint16_t DirEntryCount;        // Max root directory entries
    uint16_t TotalSector;          // Total sectors if ≤ 65535
    uint8_t MediaDescriptorType;   // Storage media identifier
    
    // FAT-specific parameters
    uint16_t SectorsPerFat;        // Size of each FAT table
    
    // Disk geometry (for BIOS compatibility)
    uint16_t SectorsPerTrack;
    uint16_t Heads;
    uint32_t HiddenSectors;        // Offset to partition
    uint32_t LargeSectorCount;     // Total sectors if > 65535
    
    // Extended boot sector fields
    uint8_t DriveNumber;           // 0x00=floppy, 0x80=HDD
    uint8_t _Reserved;             // Reserved for Windows NT
    uint8_t Signature;             // Should be 0x28 or 0x29
    uint32_t VolumeId;             // Volume serial number
    uint8_t VolumeLabel[11];       // Volume name (space padded)
    uint8_t SystemId[8];           // Filesystem type ("FAT12   ")
} __attribute__((packed)) BootSector;

// =============================================================================
// DIRECTORY ENTRY STRUCTURE
// =============================================================================
// Represents a file or directory entry in FAT12. Each entry contains
// metadata including 8.3 format filename, attributes, timestamps, and
// cluster allocation information.

typedef struct {
    uint8_t Name[11];              // 8.3 filename (no dot, space padded)
    uint8_t Attributes;            // File attributes bitmap
    uint8_t _reserved;             // Reserved for future use
    uint8_t CreatedTimeTenths;     // Tenths of seconds (0-199)
    uint16_t CreatedTime;          // Creation time (hour/min/sec packed)
    uint16_t CreatedDate;          // Creation date (year/month/day packed)
    uint16_t AccessDate;           // Last access date
    uint16_t FirstClusterHigh;     // High word of first cluster (FAT32)
    uint16_t FirstClusterLow;      // First cluster number (FAT12/FAT16)
    uint16_t ModifiedTime;         // Last modification time
    uint16_t ModifiedDate;         // Last modification date
    uint32_t Size;                 // File size in bytes
} __attribute__((packed)) DirectoryEntry;

// =============================================================================
// GLOBAL VARIABLES
// =============================================================================

BootSector g_BootSector;           // Boot sector metadata
uint8_t* g_Fat = NULL;             // File Allocation Table data
DirectoryEntry* g_RootDirectory = NULL;  // Root directory entries
uint32_t g_RootDirectoryEnd;       // LBA after root directory (data area start)

// =============================================================================
// DISK I/O FUNCTIONS
// =============================================================================

/**
 * Reads the boot sector from disk image
 * 
 * @param disk File pointer to open disk image
 * @return true if successful, false on error
 */
bool read_boot_sector(FILE* disk) {
    return fread(&g_BootSector, sizeof(g_BootSector), 1, disk) > 0;
}

/**
 * Reads sectors from disk image starting at specified LBA
 * 
 * @param disk File pointer to open disk image
 * @param lba Starting Logical Block Address (sector number)
 * @param count Number of sectors to read
 * @param buffer_out Output buffer for read data
 * @return true if successful, false on error
 */
bool read_sectors(FILE* disk, uint32_t lba, uint32_t count, void* buffer_out) {
    bool success = true;
    
    // Seek to starting sector
    success = success && (fseek(disk, lba * g_BootSector.BytesPerSector, SEEK_SET) == 0);
    
    // Read specified number of sectors
    success = success && (fread(buffer_out, g_BootSector.BytesPerSector, count, disk) == count);
    
    return success;
}

/**
 * Reads File Allocation Table from disk
 * 
 * @param disk File pointer to open disk image
 * @return true if successful, false on error
 */
bool read_fat(FILE* disk) {
    uint32_t fat_size = g_BootSector.SectorsPerFat * g_BootSector.BytesPerSector;
    g_Fat = (uint8_t*)malloc(fat_size);
    
    if (g_Fat == NULL) {
        return false;
    }
    
    return read_sectors(disk, g_BootSector.ReservedSectors, 
                       g_BootSector.SectorsPerFat, g_Fat);
}

/**
 * Reads root directory from disk
 * 
 * @param disk File pointer to open disk image
 * @return true if successful, false on error
 */
bool read_root_directory(FILE* disk) {
    // Calculate root directory LBA (after reserved sectors and FATs)
    uint32_t lba = g_BootSector.ReservedSectors + 
                   g_BootSector.SectorsPerFat * g_BootSector.FatCount;
    
    // Calculate required sectors for root directory
    uint32_t dir_size = sizeof(DirectoryEntry) * g_BootSector.DirEntryCount;
    uint32_t sectors = dir_size / g_BootSector.BytesPerSector;
    
    // Add extra sector if directory doesn't align perfectly
    if (dir_size % g_BootSector.BytesPerSector > 0) {
        sectors++;
    }
    
    // Store data area starting LBA
    g_RootDirectoryEnd = lba + sectors;
    
    // Allocate memory for root directory
    g_RootDirectory = (DirectoryEntry*)malloc(sectors * g_BootSector.BytesPerSector);
    
    if (g_RootDirectory == NULL) {
        return false;
    }
    
    return read_sectors(disk, lba, sectors, g_RootDirectory);
}

// =============================================================================
// FILE OPERATION FUNCTIONS
// =============================================================================

/**
 * Converts regular filename to FAT12 8.3 format
 * 
 * @param input Original filename (e.g., "test.txt")
 * @param output Output buffer for FAT12 name (11 bytes)
 */
void to_fat12_name(const char* input, char* output) {
    // Initialize with spaces
    memset(output, ' ', 11);
    
    const char* dot = strchr(input, '.');
    
    if (dot == NULL) {
        // No extension - copy name only (max 8 chars)
        int name_len = strlen(input);
        if (name_len > 8) name_len = 8;
        memcpy(output, input, name_len);
    } else {
        // Has extension - copy name and extension
        int name_len = dot - input;
        if (name_len > 8) name_len = 8;
        memcpy(output, input, name_len);
        
        int ext_len = strlen(dot + 1);
        if (ext_len > 3) ext_len = 3;
        memcpy(output + 8, dot + 1, ext_len);
    }
    
    // Convert to uppercase
    for (int i = 0; i < 11; i++) {
        output[i] = toupper(output[i]);
    }
}

/**
 * Searches for file in root directory
 * 
 * @param name Filename in FAT12 8.3 format (11 characters)
 * @return Pointer to directory entry if found, NULL otherwise
 */
DirectoryEntry* find_file(const char* name) {
    for (uint32_t i = 0; i < g_BootSector.DirEntryCount; i++) {
        if (memcmp(name, g_RootDirectory[i].Name, 11) == 0) {
            return &g_RootDirectory[i];
        }
    }
    return NULL;
}

/**
 * Reads file contents by following FAT cluster chain
 * 
 * @param file_entry Pointer to file's directory entry
 * @param disk File pointer to open disk image
 * @param output_buffer Buffer to store file contents
 * @return true if successful, false on error
 */
bool read_file(DirectoryEntry* file_entry, FILE* disk, uint8_t* output_buffer) {
    bool success = true;
    uint16_t current_cluster = file_entry->FirstClusterLow;
    uint32_t cluster_size = g_BootSector.SectorsPerCluster * g_BootSector.BytesPerSector;
    
    do {
        // Calculate cluster LBA (data area starts at cluster 2)
        uint32_t lba = g_RootDirectoryEnd + (current_cluster - 2) * g_BootSector.SectorsPerCluster;
        
        // Read current cluster
        success = success && read_sectors(disk, lba, g_BootSector.SectorsPerCluster, output_buffer);
        output_buffer += cluster_size;
        
        // Get next cluster from FAT (12-bit entries)
        uint32_t fat_index = current_cluster * 3 / 2;
        
        if (current_cluster % 2 == 0) {
            // Even cluster: low 12 bits
            current_cluster = (*(uint16_t*)(g_Fat + fat_index)) & 0x0FFF;
        } else {
            // Odd cluster: high 12 bits
            current_cluster = (*(uint16_t*)(g_Fat + fat_index)) >> 4;
        }
        
    } while (success && current_cluster < 0x0FF8); // Continue until EOF
    
    return success;
}

// =============================================================================
// DEBUG AND UTILITY FUNCTIONS
// =============================================================================

/**
 * Displays root directory contents for debugging
 */
void print_root_directory() {
    printf("Root Directory Contents:\n");
    printf("=======================\n");
    
    for (uint32_t i = 0; i < g_BootSector.DirEntryCount; i++) {
        // Skip empty or deleted entries
        if (g_RootDirectory[i].Name[0] == 0x00 || g_RootDirectory[i].Name[0] == 0xE5) {
            continue;
        }
        
        printf("File: ");
        for (int j = 0; j < 11; j++) {
            printf("%c", g_RootDirectory[i].Name[j]);
        }
        printf(" | Size: %u bytes\n", g_RootDirectory[i].Size);
    }
}

/**
 * Displays boot sector information
 */
void print_boot_sector_info() {
    printf("Boot Sector Information:\n");
    printf("=======================\n");
    printf("Bytes per sector:    %u\n", g_BootSector.BytesPerSector);
    printf("Sectors per cluster: %u\n", g_BootSector.SectorsPerCluster);
    printf("Reserved sectors:    %u\n", g_BootSector.ReservedSectors);
    printf("FAT count:           %u\n", g_BootSector.FatCount);
    printf("Root directory entries: %u\n", g_BootSector.DirEntryCount);
    printf("Sectors per FAT:     %u\n", g_BootSector.SectorsPerFat);
    printf("Total sectors:       %u\n", 
           g_BootSector.TotalSector ? g_BootSector.TotalSector : g_BootSector.LargeSectorCount);
}

// =============================================================================
// MAIN APPLICATION
// =============================================================================

/**
 * FAT12 Filesystem Analysis Tool
 * 
 * Usage: fat <disk_image> <file_name>
 * 
 * This tool reads FAT12 filesystem structures and extracts files from
 * disk images. It demonstrates low-level filesystem operations including
 * boot sector parsing, FAT traversal, and cluster chain reading.
 * 
 * Return codes:
 *   0  Success
 *  -1  Invalid arguments or cannot open disk
 *  -2  Boot sector read error
 *  -3  FAT read error
 *  -4  Root directory read error
 *  -5  File not found error
 *  -6  File read error
 */
int main(int argc, char** argv) {
    // Validate command line arguments
    if (argc < 3) {
        printf("Usage: %s <disk_image> <file_name>\n", argv[0]);
        printf("Example: %s floppy.img README.TXT\n", argv[0]);
        return -1;
    }
    
    // Open disk image
    FILE* disk = fopen(argv[1], "rb");
    if (!disk) {
        fprintf(stderr, "Error: Cannot open disk image '%s'\n", argv[1]);
        return -1;
    }
    
    // Read boot sector
    if (!read_boot_sector(disk)) {
        fprintf(stderr, "Error: Failed to read boot sector\n");
        fclose(disk);
        return -2;
    }
    
    // Display filesystem information
    print_boot_sector_info();
    printf("\n");
    
    // Read File Allocation Table
    if (!read_fat(disk)) {
        fprintf(stderr, "Error: Failed to read FAT\n");
        fclose(disk);
        return -3;
    }
    
    // Read root directory
    if (!read_root_directory(disk)) {
        fprintf(stderr, "Error: Failed to read root directory\n");
        free(g_Fat);
        fclose(disk);
        return -4;
    }
    
    // Display directory contents for debugging
    print_root_directory();
    printf("\n");
    
    // Convert filename to FAT12 format and search
    char fat_name[11];
    to_fat12_name(argv[2], fat_name);
    
    printf("Searching for: ");
    for (int i = 0; i < 11; i++) {
        printf("%c", fat_name[i]);
    }
    printf("\n");
    
    DirectoryEntry* file_entry = find_file(fat_name);
    if (!file_entry) {
        fprintf(stderr, "Error: File '%s' not found in root directory\n", argv[2]);
        free(g_Fat);
        free(g_RootDirectory);
        fclose(disk);
        return -5;
    }
    
    printf("File found! Size: %u bytes\n\n", file_entry->Size);
    
    // Read file contents
    uint8_t* buffer = (uint8_t*)malloc(file_entry->Size + g_BootSector.BytesPerSector);
    if (!buffer) {
        fprintf(stderr, "Error: Memory allocation failed\n");
        free(g_Fat);
        free(g_RootDirectory);
        fclose(disk);
        return -6;
    }
    
    if (!read_file(file_entry, disk, buffer)) {
        fprintf(stderr, "Error: Failed to read file '%s'\n", argv[2]);
        free(buffer);
        free(g_Fat);
        free(g_RootDirectory);
        fclose(disk);
        return -6;
    }
    
    // Display file contents
    printf("File contents:\n");
    printf("==============\n");
    for (size_t i = 0; i < file_entry->Size; i++) {
        if (isprint(buffer[i])) {
            fputc(buffer[i], stdout);
        } else {
            printf("<%02x>", buffer[i]);
        }
    }
    printf("\n");
    
    // Cleanup resources
    free(buffer);
    free(g_Fat);
    free(g_RootDirectory);
    fclose(disk);
    
    return 0;
}