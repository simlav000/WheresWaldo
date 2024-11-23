# Group #
.data
displayBuffer:  .space 0x40000 # space for 512x256 bitmap display 
errorBuffer:    .space 0x40000 # space to store match function
templateBuffer: .space 0x100   # space for 8x8 template
imageFileName:    .asciiz "pxlcon512x256cropgs.raw" 
templateFileName: .asciiz "template8x8gs.raw"
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
	jal matchTemplate        # MATCHING DONE HERE
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
    lw $s0, 0($a0)       # $s0 = image buffer
    lw $s1, 4($a0)       # $s1 = image width
    lw $s2, 8($a0)       # $s2 = image height

    # Load template buffer
    lw $s3, 0($a1)       # $s3 = template buffer

    # Load error buffer
    lw $s4, 0($a2)       # $s4 = error buffer

    subi $s5, $s2, 8     # $s5 = height - 8
    subi $s6, $s1, 8     # $s6 = width - 8

    # Outer loop:
    li $t0, 0            # $t0: int y = 0

outer_y_loop:
    bgt $t0, $s5, done   # if y > height - 8, break

    # Inner loop: x
    li $t1, 0            # $t1: int x = 0

inner_x_loop:
    bgt $t1, $s6, outer_y_continue

    # Reinitialize SAD after each template coverage
    li $t7, 0            # $t7 = SAD accumulator

    li $t2, 0            # $t2 : int j = 0 (template row index)

compute_sad_row:
    bge $t2, 8, sad_done # if j >= 8, done

    li $t3, 0            # $t4 : int i = 0 (template column index)

compute_sad_col:
    bge $t3, 8, next_row # if i >= 8, done

    # We have to imagine that image is flattened into a 1D array, so when
    # we iterate over the width of the template and want to "move down",
    # we have to jump over an entire image width to obtain the correct pixel
    # Thus the pixel index is given by:
    # (y + j) * width + (x + i)
    add $t4, $t0, $t2      # $t4 = (y + j)
    mul $t4, $t4, $s1      # $t4 = (y + j) * width
    add $t4, $t4, $t1      # $t4 = (y + j) * width + x
    add $t4, $t4, $t3      # $t4 = (y + j) * width + (x + i)
    sll $t4, $t4, 2        # Multiply by 4 for byte offset
    add $t4, $t4, $s0      # $t4 = pixel relative to memory location of image

    # Same idea for template, but this time the width is known so we jump
    # by units of 8 each time we move down a row of the template.
    # Compute the template index: j * 8 + i
    mul $t5, $t2, 8        # $t5 = j * 8
    add $t5, $t5, $t3      # $t5 = j * 8 + i
    sll $t5, $t5, 2        # Multiply by 4 for byte offset
    add $t5, $t5, $s3      # $t5 = pixel relative to memory location of template

    # Compute SAD: abs(image - template)
    lb $t6, 0($t4)          # Load image pixel into $t6
    lb $t7, 0($t5)          # Load template pixel into $t7
    sub $t8, $t6, $t7      # $t8 = image - template
    abs $t8, $t8           # Take absolute value
    add $t7, $t7, $t8      # Accumulate SAD into $t7

    addi $t3, $t3, 1       # Increment template column index (i)
    j compute_sad_col      # Repeat for the next column

next_row:
    addi $t2, $t2, 1       # Increment template row index (j)
    j compute_sad_row      # Repeat for the next row

sad_done:
    # Store the computed SAD value in the error buffer
    mul $t4, $t0, $s6      # $t4 = y * (width - 8)
    add $t4, $t4, $t1      # $t4 = y * (width - 8) + x
    sll $t4, $t4, 2        # Multiply by 4 for byte offset
    add $t4, $t4, $s4      # $t4 = address in the error buffer
    sw $t7, 0($t4)         # Store SAD value

    addi $t1, $t1, 1       # Increment x (search window column index)
    j inner_x_loop         # Repeat for the next x position

outer_y_continue:
    addi $t0, $t0, 1       # Increment y (search window row index)
    j outer_y_loop         # Repeat for the next y position

done:
    jr $ra                 # Return from the function	

##########################################################
# matchTemplateFast( bufferInfo imageBufferInfo, bufferInfo templateBufferInfo, bufferInfo errorBufferInfo )
# NOTE: struct bufferInfo { int *buffer, int width, int height, char* filename }
matchTemplateFast:	
	
	# TODO: write this function!
	
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