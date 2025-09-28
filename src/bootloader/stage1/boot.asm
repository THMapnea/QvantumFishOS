; =============================================================================
; BOOTLOADER FOR NBOS OPERATING SYSTEM
; =============================================================================
;
; This bootloader follows the FAT12 standard for 1.44MB floppy disks
; and resides in the boot sector (sector 0) of the disk.
;
; Structure:
; - BPB (BIOS Parameter Block): filesystem information
; - Bootstrap code: loads and starts the kernel
; - Boot signature: 0xAA55 (required by BIOS)
;
; The bootloader is loaded by BIOS at address 0x7C00
; and must be exactly 512 bytes (sector size)

org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A



; =============================================================================
; BIOS PARAMETER BLOCK (BPB)
; =============================================================================
;
; The BPB contains critical information about the FAT12 filesystem
; needed to locate and load the kernel from disk

jmp short start                                    ; Jump over BPB data to avoid executing it as code (2 bytes)
nop                                                ; Pad to ensure BPB starts at correct offset (1 byte)

; Standard BPB for FAT12 on 1.44MB floppy
bdb_oem:                    db 'MSWIN4.1'          ; OEM identifier (8 bytes)
bdb_bytes_per_sector:       dw 512                 ; Sector size in bytes
bdb_sectors_per_cluster:    db 1                   ; Sectors per cluster
bdb_reserved_sectors:       dw 1                   ; Reserved sectors (bootloader)
bdb_fat_count:              db 2                   ; Number of FAT copies
bdb_dir_entries_count:      dw 0E0h                ; Root directory entries (224)
bdb_total_sectors:          dw 2880                ; Total sectors (1.44MB)
bdb_media_descriptor_type:  db 0F0h                ; Media type (3.5" floppy)
bdb_sectors_per_fat:        dw 9                   ; Sectors per FAT
bdb_sectors_per_track:      dw 18                  ; Sectors per track
bdb_heads:                  dw 2                   ; Heads
bdb_hidden_sectors:         dd 0                   ; Hidden sectors
bdb_large_sector_count:     dd 0                   ; Large sector count

; Extended Boot Record
ebr_drive_number:           db 0                   ; Drive number (0 = floppy)
                            db 0                   ; Reserved
ebr_signature:              db 29h                 ; Signature
ebr_volume_id:              db 12h, 34h, 56h, 78h  ; Volume ID (serial number)
ebr_volume_label:           db 'QvantumFish'       ; Volume label (11 bytes)
ebr_system_id:              db 'FAT12   '          ; Filesystem type (8 bytes)



; =============================================================================
; BOOTSTRAP CODE
; =============================================================================
;
; Main bootloader code that:
; 1. Initializes registers and stack
; 2. Displays welcome message
; 3. Loads kernel from FAT12 filesystem
; 4. Transfers execution to kernel



; =============================================================================
; MAIN FUNCTION
; =============================================================================

start:
    ; Initialize data segments
    mov ax, 0                   ; Load 0 in the accumulator register to initialize
    mov ds, ax                  ; Set the data segment register to 0
    mov es, ax                  ; Set the extra segment register to 0

    ; Initialize stack
    mov ss, ax                  ; Set the stack pointer to 0
    mov sp, 0x7C00              ; Stack grows downward from 0x7C00

    push es
    push word .after
    retf

.after:
    ; Save boot drive number
    mov [ebr_drive_number], dl  ; Store drive number provided by BIOS

    ; Show loading message
    mov si, msg_loading         ; Load the message in the SI register
    call puts                   ; Display loading message

    ; Get disk parameters
    push es
    mov ah, 08h                 ; BIOS function: get drive parameters
    int 13h                     ; Call BIOS disk service
    jc floppy_error             ; Jump to error handler if operation failed
    pop es

    ; Extract sectors per track
    and cl, 0x3f                ; Mask upper 2 bits (cylinder bits)
    xor ch, ch                  ; Clear CH register
    mov [bdb_sectors_per_track], cx  ; Store sectors per track

    ; Extract number of heads
    inc dh                      ; Heads are 0-based, so increment to get count
    mov [bdb_heads], dh         ; Store number of heads

    ; Calculate root directory location
    ; First, compute FAT size: sectors_per_fat * fat_count
    mov ax, [bdb_sectors_per_fat]  ; Load sectors per FAT
    mov bl, [bdb_fat_count]        ; Load number of FATs
    xor bh, bh                     ; Clear upper byte of BX
    mul bx                         ; AX = sectors_per_fat * fat_count
    add ax, [bdb_reserved_sectors] ; Add reserved sectors (boot sector)
    push ax                        ; Save FAT location + reserved sectors

    ; Calculate root directory size in sectors
    mov ax, [bdb_dir_entries_count] ; Load number of directory entries
    shl ax, 5                      ; Multiply by 32 (bytes per entry)
    xor dx, dx                     ; Clear DX for division
    div word [bdb_bytes_per_sector] ; Divide by sector size to get sectors

    ; Round up if there's a remainder
    test dx, dx                    ; Check if remainder is zero
    jz .root_dir_after            ; If no remainder, skip increment
    inc ax                        ; Increment to account for partial sector

.root_dir_after:
    ; Read root directory into memory
    mov cl, al                    ; Number of sectors to read (root directory size)
    pop ax                        ; Restore starting sector (after FAT)
    mov dl, [ebr_drive_number]    ; Load drive number
    mov bx, buffer                ; Load destination buffer address
    call disk_read                ; Read root directory sectors

    ; Search for kernel file in root directory
    xor bx, bx                    ; Clear BX (entry counter)
    mov di, buffer                ; Point DI to start of directory buffer

.search_kernel:
    mov si, file_kernel_bin       ; Point SI to kernel filename
    mov cx, 11                    ; Compare 11 characters (8.3 format)
    push di                       ; Save current directory entry position
    repe cmpsb                    ; Compare strings
    pop di                        ; Restore directory entry position
    je .found_kernel              ; Jump if kernel file found

    ; Move to next directory entry
    add di, 32                    ; Each directory entry is 32 bytes
    inc bx                        ; Increment entry counter
    cmp bx, [bdb_dir_entries_count] ; Check if all entries searched
    jl .search_kernel             ; Continue searching if more entries

    ; Kernel not found - display error
    jmp kernel_not_found_error

.found_kernel:
    ; Extract kernel cluster number from directory entry
    mov ax, [di + 26]             ; Cluster number is at offset 26
    mov [kernel_cluster], ax      ; Store kernel starting cluster

    ; Read FAT into memory
    mov ax, [bdb_reserved_sectors] ; Start of FAT (after boot sector)
    mov bx, buffer                ; Destination buffer
    mov cl, [bdb_sectors_per_fat] ; Number of FAT sectors to read
    mov dl, [ebr_drive_number]    ; Drive number
    call disk_read                ; Read FAT into buffer

    ; Set up segment for kernel loading
    mov bx, KERNEL_LOAD_SEGMENT   ; Load kernel segment
    mov es, bx                    ; Set ES to kernel segment
    mov bx, KERNEL_LOAD_OFFSET    ; Load kernel offset

.load_kernel_loop:
    ; Convert cluster to LBA address
    mov ax, [kernel_cluster]      ; Load current cluster number
    add ax, 31                    ; Add data area offset (hardcoded for FAT12)

    ; Read cluster sector
    mov cl, 1                     ; Read one sector
    mov dl, [ebr_drive_number]    ; Drive number
    call disk_read                ; Read cluster sector

    ; Advance buffer pointer
    add bx, [bdb_bytes_per_sector] ; Move to next sector in memory

    ; Find next cluster in FAT chain
    mov ax, [kernel_cluster]      ; Load current cluster
    mov cx, 3                     ; Multiply by 3 (each FAT12 entry is 1.5 bytes)
    mul cx                        ; AX = cluster * 3
    mov cx, 2                     ; Divide by 2 to get byte offset
    div cx                        ; AX = byte offset in FAT

    ; Calculate FAT entry address
    mov si, buffer                ; Point to FAT buffer
    add si, ax                    ; Add byte offset
    mov ax, [ds:si]               ; Load FAT entry (2 bytes)

    ; Check if cluster was even or odd
    or dx, dx                     ; Check remainder from division
    jz .even                      ; Jump if even cluster

.odd:
    shr ax, 4                     ; Odd cluster: shift right 4 bits
    jmp .next_cluster_after       ; Continue processing

.even:
    and ax, 0x0FFF                ; Even cluster: mask upper 4 bits

.next_cluster_after:
    ; Check for end of cluster chain
    cmp ax, 0x0FF8                ; Compare with end of chain marker
    jae .read_finish              ; Jump if end of chain reached

    ; Continue with next cluster
    mov [kernel_cluster], ax      ; Store next cluster number
    jmp .load_kernel_loop         ; Continue loading

.read_finish:
    ; Prepare for kernel execution
    mov dl, [ebr_drive_number]    ; Pass drive number to kernel
    mov ax, KERNEL_LOAD_SEGMENT   ; Set up segments for kernel
    mov ds, ax                    ; Set data segment to kernel segment
    mov es, ax                    ; Set extra segment to kernel segment

    ; Jump to kernel entry point
    jmp KERNEL_LOAD_SEGMENT:KERNEL_LOAD_OFFSET

    ; Fallback: reboot if kernel doesn't start
    jmp wait_key_and_reboot
    cli                           ; Disable interrupts
    hlt                           ; Halt processor



; =============================================================================
; ERROR HANDLING ROUTINES
; =============================================================================

floppy_error:
    mov si, msg_floppy_read_failed     ; Load error message string
    call puts                          ; Display error message
    jmp wait_key_and_reboot            ; Jump to reboot handler

kernel_not_found_error:
    mov si, msg_kernel_not_found       ; Load kernel not found message
    call puts                          ; Display error message
    jmp wait_key_and_reboot            ; Jump to reboot handler

wait_key_and_reboot:
    mov ah, 0                          ; BIOS function: wait for keypress
    int 16h                            ; Call BIOS keyboard service
    jmp 0FFFFh:0                       ; Jump to BIOS reset vector (reboot system)
    cli                                ; Disable interrupts
    hlt                                ; Halt execution



; =============================================================================
; PUTS FUNCTION
; =============================================================================
;
; Prints a null-terminated string to video using BIOS teletype output
; Parameters:
;   ds:si - pointer to null-terminated string to print

puts:
    push si                 ; Save SI register value
    push ax                 ; Save AX register value

.loop:
    lodsb                   ; Load byte from [SI] into AL, increment SI
    or al, al               ; Check for end of string (AL = 0)
    jz .done                ; Jump to done if end of string reached

    mov ah, 0x0e            ; BIOS teletype output function
    mov bh, 0               ; Video page 0
    int 0x10                ; Call BIOS video service

    jmp .loop               ; Continue with next character

.done:
    pop ax                  ; Restore AX register value
    pop si                  ; Restore SI register value
    ret                     ; Return from function



; =============================================================================
; DISK OPERATION ROUTINES
; =============================================================================

; LBA to CHS conversion function
; Converts Logical Block Addressing to Cylinder-Head-Sector addressing
; Parameters:
;   ax: LBA address to convert
; Returns:
;   cx [bits 0-5]: sector number
;   cx [bits 6-15]: cylinder number
;   dh: head number

lba_to_chs:
    push ax                             ; Save original LBA value
    push dx                             ; Save DX register

    xor dx, dx                          ; Clear DX for division
    div word [bdb_sectors_per_track]    ; AX = LBA / sectors per track
                                        ; DX = LBA % sectors per track (sector number - 1)
    inc dx                              ; DX = sector number (1-based)
    mov cx, dx                          ; Store sector number in CL
    
    xor dx, dx                          ; Clear DX for division
    div word [bdb_heads]                ; AX = cylinder number
                                        ; DX = head number
    mov dh, dl                          ; Store head number in DH
    mov ch, al                          ; Store lower 8 bits of cylinder in CH
    shl ah, 6                           ; Shift upper 2 bits of cylinder to bits 6-7
    or cl, ah                           ; Combine sector and cylinder bits in CL

    pop ax                              ; Restore original DX value
    mov dl, al                          ; Move drive number to DL
    pop ax                              ; Restore original AX value
    ret                                 ; Return from function

; Disk read function
; Reads sectors from disk using BIOS interrupt 13h
; Parameters:
;   ax: LBA address to read from
;   cl: number of sectors to read (up to 128)
;   dl: drive number
;   es:bx: memory address where data will be stored

disk_read:
    push ax                             ; Save registers that will be modified
    push bx                             ; Save BX register
    push cx                             ; Save CX register
    push dx                             ; Save DX register
    push di                             ; Save DI register

    push cx                             ; Save sector count
    call lba_to_chs                     ; Convert LBA to CHS format
    pop ax                              ; AL = number of sectors to read
    mov ah, 02h                         ; BIOS function: read sectors
    mov di, 3                           ; Retry counter (3 attempts)

.retry:
    pusha                               ; Save all registers
    stc                                 ; Set carry flag (some BIOSes require this)
    int 13h                             ; Call BIOS disk service
    jnc .done                           ; Jump if operation succeeded

    ; Operation failed - retry
    popa                                ; Restore registers
    call disk_reset                     ; Reset disk controller
    dec di                              ; Decrement retry counter
    test di, di                         ; Check if retries exhausted
    jnz .retry                          ; Retry if attempts remaining

.fail:
    jmp floppy_error                    ; Jump to error handler

.done:
    popa                                ; Restore registers saved by pusha
    
    pop di                              ; Restore original register values
    pop dx                              ; Restore DX register
    pop cx                              ; Restore CX register
    pop bx                              ; Restore BX register
    pop ax                              ; Restore AX register
    ret                                 ; Return from function

; Disk reset function
; Resets the disk controller using BIOS interrupt 13h
; Parameters: None
; Returns: None (carry flag indicates success/failure)
disk_reset:
    pusha                               ; Save all general-purpose registers
    mov ah, 0                           ; BIOS function: reset disk system
    stc                                 ; Set carry flag
    int 13h                             ; Call BIOS disk service
    jc floppy_error                     ; Jump to error handler if reset failed
    popa                                ; Restore all general-purpose registers
    ret                                 ; Return from function



; =============================================================================
; DATA SECTION - MESSAGES AND CONSTANTS
; =============================================================================

msg_loading:            db 'Qvantum Loading...', ENDL, 0
msg_floppy_read_failed: db 'Failed to read from floppy', ENDL, 0
msg_kernel_not_found:   db 'STAGE2.bin file not found', ENDL, 0
file_kernel_bin:        db 'STAGE2  BIN'        ; stage 2 filename in 8.3 format
kernel_cluster:         dw 0                    ; Storage for stage 2 starting cluster

; Kernel loading address constants
KERNEL_LOAD_SEGMENT     equ 0x2000              ; Segment where kernel will be loaded
KERNEL_LOAD_OFFSET      equ 0                   ; Offset within segment



; =============================================================================
; BOOT SIGNATURE AND BUFFER SPACE
; =============================================================================
;
; BIOS requires boot sectors to end with signature 0xAA55
; in the last two bytes to identify as bootable

times 510-($-$$) db 0       ; Fill remainder of sector with zeros
dw 0AA55h                   ; Boot signature (little endian)

; Buffer space for FAT and directory operations
buffer: