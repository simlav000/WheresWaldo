# Group #
.data
displayBuffer:  .space 0x40000 # space for 512x256 bitmap display 
errorBuffer:    .space 0x40000 # space to store match function
templateBuffer: .space 0x100   # space for 8x8 template
imageFileName:    .asciiz "pxlcon512x256cropgs.raw" 
templateFileName: .asciiz "template8x8gsLRtest.raw"
# struct bufferInfo { int *buffer, int width, int height, char* filename }
imageBufferInfo:    .word displayBuffer  512 128  imageFileName
errorBufferInfo:    .word errorBuffer    512 128  0
templateBufferInfo: .word templateBuffer 8   8    templateFileName

.text
main:	la $a0, imageBufferInfo
	jal loadImage
	la $a0, templateBufferInfo
	jal loadImage
	la $a0, imageBufferInfo
	la $a1, templateBufferInfo
	la $a2, errorBufferInfo
	jal matchTemplateFast        # MATCHING DONE HERE
	la $a0, errorBufferInfo
	jal findBest
	la $a0, imageBufferInfo
	move $a1, $v0
	jal highlight
	la $a0, errorBufferInfo	
	jal processError
	li $v0, 10		# exit
	syscall
	

##########################################################
# matchTemplate( bufferInfo imageBufferInfo, bufferInfo templateBufferInfo, bufferInfo errorBufferInfo )
# NOTE: struct bufferInfo { int *buffer, int width, int height, char* filename }
matchTemplate:
    # Load image buffer, width, and height
    lw $s0, 0($a0)      # $s0 = image buffer
    lw $s1, 4($a0)      # $s1 = image width
    lw $s2, 8($a0)      # $s2 = image height

    # Load template buffer
    lw $s3, 0($a1)      # $s3 = template buffer

    # Load error buffer
    lw $s4, 0($a2)      # $s4 = error buffer

    # Outer loop: y
    li $t0, 0           # $t0 : int y = 0 (image row index)

outer_y_loop:
    blt $s2, $t0, done  # if image height < y, break
    sub $s5, $s2, 8     # $s5 = height - 8
    bgt $t0, $s5, done  # if y > height - 8, break

    # Inner loop: x
    li $t1, 0           # $t1 : int x = 0 (image column index)
inner_x_loop:
    sub $s6, $s1, 8     # $s6 = width - 8
    bgt $t1, $s6, outer_y_continue

    li $t9, 0           # $t9 : SAD accumulator

    li $t2, 0           # $t2 : int j = 0 (template row index)

compute_sad_row:
    # if j >= 8, slide template over image by one pixel
    # Store SAD in error buffer then reset it.
    bge $t2, 8, sad_done

    li $t3, 0           # $t3 : int i = 0 (template column index)

compute_sad_col:
    # if i >= 8, slide over to next row
    bge $t3, 8, next_row

    # Entire image is flattened into 1D array in memory. When j increments,
    # we need to jump over the 1D array by the width of the image to catch
    # the next row. Thus the pixel index as a function of y, x, j and i is:
    # (y + j) * width + (x + i)
    add $t4, $t0, $t2   # $a0 = (y + j)
    mul $t4, $t4, $s1   # $a0 = (y + j) * width
    add $t4, $t4, $t1   # $a0 = (y + j) * width + x
    add $t4, $t4, $t3   # $a0 = (y + j) * width + (x + i)
    sll $t4, $t4, 2     # Multiply by 4 bytes for word alignment
    add $t4, $t4, $s0   # Index is relative to image buffer address in memory

    # The same applies to the template, which is also flattened into an int[64]
    # array instead of some 2D 8x8 array. We again jump by its width, namely 8
    mul $t5, $t2, 8     # $a1 = j * 8
    add $t5, $t5, $t3   # $a1 = j * 8 + i
    sll $t5, $t5, 2     # Multiply by 4 bytesr for word alignment
    add $t5, $t5, $s3   # Index is relative to template buffer address in memry

    # Compute SAD: abs(image - template)
    lb $t6, 0($t4)      # Load image pixel
    lb $t7, 0($t5)      # Load template pixel
    sub $t8, $t6, $t7   # image - template
    abs $t8, $t8        # Absolute value
    add $t9, $t9, $t8   # Accumulate SAD

    addi $t3, $t3, 1    # i++
    j compute_sad_col

next_row:
    addi $t2, $t2, 1    # j++
    j compute_sad_row

sad_done:
    # Store SAD in error buffer. Error buffer shares characteristics of image.
    # Out of t registers at this point. Overwriting $t4. No conflict since we
    # loop back by this point.
    mul $t4, $t0, $s1   # $t4 = y * width
    add $t4, $t4, $t1   # $t4 += x
    sll $t4, $t4, 2     # Byte offset
    add $t4, $t4, $s4   # Index is relative to error buffer address in memory
    sw $t9, 0($t4)      # Store SAD at offset

    addi $t1, $t1, 1    # x++
    j inner_x_loop

outer_y_continue:
    addi $t0, $t0, 1    # y++
    j outer_y_loop

done:
    jr $ra
##########################################################
# matchTemplateFast( bufferInfo imageBufferInfo, bufferInfo templateBufferInfo, bufferInfo errorBufferInfo )
# NOTE: struct bufferInfo { int *buffer, int width, int height, char* filename }
matchTemplateFast:	
    # Save return address
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # Load image and template information
    lw $s0, 0($a0)       # Image buffer base address
    lw $s1, 4($a0)       # Image width
    lw $s2, 8($a0)       # Image height
    lw $s3, 0($a1)       # Template buffer base address
    lw $s4, 0($a2)       # Error buffer base address

    # Calculate boundaries
    addi $s5, $s1, -8    # Max x-coordinate (width - 8)
    addi $s6, $s2, -8    # Max y-coordinate (height - 8)

    # Iterate over template rows (j)
    li $t0, 0            # j = 0
row_loop_fast:
    bge $t0, 8, fast_done # Exit if j >= 8

    # Load template row into registers
    mul $t1, $t0, 8      # j * template width (8)
    add $t2, $s3, $t1    # Address of template row
    lb $t3, 0($t2)       # T[0][j]
    lb $t4, 1($t2)       # T[1][j]
    lb $t5, 2($t2)       # T[2][j]
    lb $t6, 3($t2)       # T[3][j]
    lb $t7, 4($t2)       # T[4][j]
    lb $t8, 5($t2)       # T[5][j]
    lb $t9, 6($t2)       # T[6][j]
    lb $t2, 7($t2)       # T[7][j]

    # Iterate over y
    li $t1, 0            # y = 0
inner_y_loop:
    bgt $t1, $s6, next_row_fast # Exit if y > height - 8

    # Iterate over x
    li $t2, 0            # x = 0
inner_x_loops:
    bgt $t2, $s5, next_y_fast # Exit if x > width - 8

    # Initialize SAD
    li $t4, 0            # SAD = 0

    # Compute SAD (loop unrolled)
    mul $t5, $t1, $s1    # (y * width)
    add $t5, $t5, $t2    # (y * width + x)
    sll $t5, $t5, 2      # Convert to byte offset
    add $t5, $t5, $s0    # Address in image buffer

    lb $t6, 0($t5)       # I[x+0][y+j]
    sub $t6, $t6, $t3    # I[x+0][y+j] - T[0][j]
    abs $t6, $t6         # Absolute value
    add $t4, $t4, $t6    # Accumulate SAD

    addi $t5, $t5, 4     # advance to next column
    lb $t6, 0($t5)       # I[x+1][y+j]
    sub $t6, $t6, $t4    # I[x+1][y+j] - T[1][j]
    abs $t6, $t6         # absolute value
    add $t4, $t4, $t6    # accumulate SAD

    # Repeat for columns
    addi $t5, $t5, 4
    lb $t6, 0($t5)
    sub $t6, $t6, $t5
    abs $t6, $t6
    add $t4, $t4, $t6

    addi $t5, $t5, 4
    lb $t6, 0($t5)
    sub $t6, $t6, $t6
    abs $t6, $t6
    add $t4, $t4, $t6

    addi $t5, $t5, 4
    lb $t6, 0($t5)
    sub $t6, $t6, $t7
    abs $t6, $t6
    add $t4, $t4, $t6

    addi $t5, $t5, 4
    lb $t6, 0($t5)
    sub $t6, $t6, $t8
    abs $t6, $t6
    add $t4, $t4, $t6

    addi $t5, $t5, 4
    lb $t6, 0($t5)
    sub $t6, $t6, $t9
    abs $t6, $t6
    add $t4, $t4, $t6

    addi $t5, $t5, 4
    lb $t6, 0($t5)
    sub $t6, $t6, $t2    # T[7][j]
    abs $t6, $t6
    add $t4, $t4, $t6

    # Store SAD in error buffer
    mul $t3, $t1, $s1    # y * width
    add $t3, $t3, $t2    # (y * width + x)
    sll $t3, $t3, 2      # Convert to byte offset
    add $t3, $t3, $s4    # Address in error buffer
    sw $t4, 0($t3)       # Store SAD

    # Increment x
    addi $t2, $t2, 1
    j inner_x_loop

next_y_fast:
    # Increment y
    addi $t1, $t1, 1
    j inner_y_loop

next_row_fast:
    # Increment template row (j)
    addi $t0, $t0, 1
    j row_loop_fast

fast_done:
    # Restore return address and return
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra


	
###############################################################
# loadImage( bufferInfo* imageBufferInfo )
# NOTE: struct bufferInfo { int *buffer, int width, int height, char* filename }
loadImage:	lw $a3, 0($a0)  # int* buffer
		lw $a1, 4($a0)  # int width
		lw $a2, 8($a0)  # int height
		lw $a0, 12($a0) # char* filename
		mul $t0, $a1, $a2 # words to read (width x height) in a2
		sll $t0, $t0, 2	  # multiply by 4 to get bytes to read
		li $a1, 0     # flags (0: read, 1: write)
		li $a2, 0     # mode (unused)
		li $v0, 13    # open file, $a0 is null-terminated string of file name
		syscall
		move $a0, $v0     # file descriptor (negative if error) as argument for read
  		move $a1, $a3     # address of buffer to which to write
		move $a2, $t0	  # number of bytes to read
		li  $v0, 14       # system call for read from file
		syscall           # read from file
        		# $v0 contains number of characters read (0 if end-of-file, negative if error).
        		# We'll assume that we do not need to be checking for errors!
		# Note, the bitmap display doesn't update properly on load, 
		# so let's go touch each memory address to refresh it!
		move $t0, $a3	   # start address
		add $t1, $a3, $a2  # end address
loadloop:	lw $t2, ($t0)
		sw $t2, ($t0)
		addi $t0, $t0, 4
		bne $t0, $t1, loadloop
		jr $ra
		
		
#####################################################
# (offset, score) = findBest( bufferInfo errorBuffer )
# Returns the address offset and score of the best match in the error Buffer
findBest:	lw $t0, 0($a0)     # load error buffer start address	
		lw $t2, 4($a0)	   # load width
		lw $t3, 8($a0)	   # load height
		addi $t3, $t3, -7  # height less 8 template lines minus one
		mul $t1, $t2, $t3
		sll $t1, $t1, 2    # error buffer size in bytes	
		add $t1, $t0, $t1  # error buffer end address
		li $v0, 0		# address of best match	
		li $v1, 0xffffffff 	# score of best match	
		lw $a1, 4($a0)    # load width
        		addi $a1, $a1, -7 # initialize column count to 7 less than width to account for template
fbLoop:		lw $t9, 0($t0)        # score
		sltu $t8, $t9, $v1    # better than best so far?
		beq $t8, $zero, notBest
		move $v0, $t0
		move $v1, $t9
notBest:		addi $a1, $a1, -1
		bne $a1, $0, fbNotEOL # Need to skip 8 pixels at the end of each line
		lw $a1, 4($a0)        # load width
        		addi $a1, $a1, -7     # column count for next line is 7 less than width
        		addi $t0, $t0, 28     # skip pointer to end of line (7 pixels x 4 bytes)
fbNotEOL:	add $t0, $t0, 4
		bne $t0, $t1, fbLoop
		lw $t0, 0($a0)     # load error buffer start address	
		sub $v0, $v0, $t0  # return the offset rather than the address
		jr $ra
		

#####################################################
# highlight( bufferInfo imageBuffer, int offset )
# Applies green mask on all pixels in an 8x8 region
# starting at the provided addr.
highlight:	lw $t0, 0($a0)     # load image buffer start address
		add $a1, $a1, $t0  # add start address to offset
		lw $t0, 4($a0) 	# width
		sll $t0, $t0, 2	
		li $a2, 0xff00 	# highlight green
		li $t9, 8	# loop over rows
highlightLoop:	lw $t3, 0($a1)		# inner loop completely unrolled	
		and $t3, $t3, $a2
		sw $t3, 0($a1)
		lw $t3, 4($a1)
		and $t3, $t3, $a2
		sw $t3, 4($a1)
		lw $t3, 8($a1)
		and $t3, $t3, $a2
		sw $t3, 8($a1)
		lw $t3, 12($a1)
		and $t3, $t3, $a2
		sw $t3, 12($a1)
		lw $t3, 16($a1)
		and $t3, $t3, $a2
		sw $t3, 16($a1)
		lw $t3, 20($a1)
		and $t3, $t3, $a2
		sw $t3, 20($a1)
		lw $t3, 24($a1)
		and $t3, $t3, $a2
		sw $t3, 24($a1)
		lw $t3, 28($a1)
		and $t3, $t3, $a2
		sw $t3, 28($a1)
		add $a1, $a1, $t0	# increment address to next row	
		add $t9, $t9, -1		# decrement row count
		bne $t9, $zero, highlightLoop
		jr $ra

######################################################
# processError( bufferInfo error )
# Remaps scores in the entire error buffer. The best score, zero, 
# will be bright green (0xff), and errors bigger than 0x4000 will
# be black.  This is done by shifting the error by 5 bits, clamping
# anything bigger than 0xff and then subtracting this from 0xff.
processError:	lw $t0, 0($a0)     # load error buffer start address
		lw $t2, 4($a0)	   # load width
		lw $t3, 8($a0)	   # load height
		addi $t3, $t3, -7  # height less 8 template lines minus one
		mul $t1, $t2, $t3
		sll $t1, $t1, 2    # error buffer size in bytes	
		add $t1, $t0, $t1  # error buffer end address
		lw $a1, 4($a0)     # load width as column counter
        		addi $a1, $a1, -7  # initialize column count to 7 less than width to account for template
pebLoop:		lw $v0, 0($t0)        # score
		srl $v0, $v0, 5       # reduce magnitude 
		slti $t2, $v0, 0x100  # clamp?
		bne  $t2, $zero, skipClamp
		li $v0, 0xff          # clamp!
skipClamp:	li $t2, 0xff	      # invert to make a score
		sub $v0, $t2, $v0
		sll $v0, $v0, 8       # shift it up into the green
		sw $v0, 0($t0)
		addi $a1, $a1, -1        # decrement column counter	
		bne $a1, $0, pebNotEOL   # Need to skip 8 pixels at the end of each line
		lw $a1, 4($a0)        # load width to reset column counter
        		addi $a1, $a1, -7     # column count for next line is 7 less than width
        		addi $t0, $t0, 28     # skip pointer to end of line (7 pixels x 4 bytes)
pebNotEOL:	add $t0, $t0, 4
		bne $t0, $t1, pebLoop
		jr $ra




