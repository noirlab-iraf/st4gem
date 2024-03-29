include	<syserr.h>
include	<imhdr.h>
include	<imio.h>
include	<fset.h>
include	<mach.h>
include	"gi.h"

define	NBITS_CHAR	(SZB_CHAR * NBITS_BYTE)

# GI_OPIX -- a take from STF_OPIX -- 
# Open a NEW_COPY pix file.
#          Open (or create) the pixel storage file.  If the image header file
# is `image.hhh' the associated pixel storage file will be `image.hhd' in the
# same directory as the header file.  STF_PFD is set if the pixel file is
# physically open.  IM_PFD is not set until we have been called by IMIO, since
# we must be called to once set up all the descriptors, even if the pixel file
# was already opened to read the GPB.
#
# dlb, 18-may-88: added code to zero out gpb's in multi-group image for groups
#   other than current; prevents strange numbers and when later programs try to
#   read the gpb of an otherwise uninitialized group of the image.
# dlb, 29-dec-1988: added code to get default set of GPB parameters and
#   correctly initialize STF-kernel descriptor.

procedure gi_opix (im, status)

pointer	im				# image descriptor
int	status				# return status

int	compress, blklen
bool	copy_of_stf_image
int	pfd, sz_gpb, group, i
pointer	stf, o_stf, o_im, ua, gpb
long	sz_pixfile, pixoff, totpix, offset

int	open(), sizeof()
errchk	open, fseti, falloc, seek, syserrs, imioff, calloc
errchk	write

begin
	status = OK
	if (IM_PFD(im) != NULL)
	    return

	o_im	 = IM_OHDR(im)
	stf	 = IM_KDES(im)
	ua	 = IM_USERAREA(im)

	pfd	 = STF_PFD(stf)
	compress = YES
	blklen   = 1
	pixoff   = 1

	switch (IM_ACMODE(im)) {
	case READ_ONLY, READ_WRITE, WRITE_ONLY, APPEND:
	    if (pfd == NULL)
		pfd = open (IM_PIXFILE(im), IM_ACMODE(im), BINARY_FILE)

	case NEW_COPY, NEW_FILE:
	    # Initialize the IMIO and STF descriptors and allocate the pixel
	    # file.

	    if (STF_NEWIMAGE(stf) == YES) {
		# Normalize IMIO header parameters for new image.
		call imioff (im, pixoff, compress, blklen)

		# Set up the required GPB parameters for the new image.
		# Note - this call can change the STF pointer.

		call stf_newimage (im)
		stf = IM_KDES(im)

		# Save the size of the old GPB user area header if we are
		# making a new copy of an old STF format image.

		copy_of_stf_image = ((IM_ACMODE(im) == NEW_COPY) &&
		    (IM_KERNEL(o_im) == IM_KERNEL(im)))

		if (copy_of_stf_image) {
		    o_stf = IM_KDES(o_im)
		    STF_PCOUNT(stf) = STF_PCOUNT(o_stf)
#		    STF_PSIZE(stf) = STF_PSIZE(o_stf)
		}

		# Open the new pixel storage file (preallocate space if
		# enabled on local system).  Save the physical pathname of
		# the pixfile in the image header, in case "imdir$" changes.

		sz_pixfile = STF_SZGROUP(stf) * STF_GCOUNT(stf)
		call falloc (IM_PIXFILE(im), sz_pixfile)

		# Zero out all remaining groups of the image
		# Open pixel file if not already open

		if (STF_PFD(stf) == NULL)
		    pfd = open (IM_PIXFILE(im), READ_WRITE, BINARY_FILE)

		# Allocate a zeroed block of memory whose length is the same
		# as that of the group parameter block

		sz_gpb = STF_PSIZE(stf) / NBITS_BYTE / SZB_CHAR
		call calloc (gpb, sz_gpb, TY_CHAR)
	
		# Zero out every group except the current one.
		do group = 1, STF_GCOUNT(stf) {
		    if (group != STF_GROUP(stf)) {
			offset = (group * STF_SZGROUP(stf) + 1) - sz_gpb
			call seek (pfd, offset)
			call write (pfd, Memc[gpb], sz_gpb)
		    }
		}

		# Free the block of memory.
		call mfree (gpb, TY_CHAR)

	    } else {
		# If we are writing to a group of an existing multigroup image,
		# verify that the important image parameters have not been
		# changed.

		if (STF_NAXIS(stf) != IM_NDIM(im))
		    call syserrs (SYS_IMGSZNEQ, IM_NAME(im))
		do i = 1, IM_NDIM(im)
		    if (STF_LENAXIS(stf,i) != IM_LEN(im,i))
			call syserrs (SYS_IMGSZNEQ, IM_NAME(im))

		# Added 5/15/87--dlb to get correct size of each data portion
		# of a group if image opened NEW_COPY and input file was a
		# template of a different dimensionality used to get GPB.
		# Compute the size of each group in the pixel file, in chars.

		totpix = IM_LEN(im,1)
		do i = 2, IM_NDIM(im)
		    totpix = totpix * IM_LEN(im,i)

		STF_SZGROUP(stf) = totpix * sizeof (IM_PIXTYPE(im)) +
		    STF_PSIZE(stf) / (SZB_CHAR * NBITS_BYTE)
	    }

	    if (pfd == NULL)
		pfd = open (IM_PIXFILE(im), READ_WRITE, BINARY_FILE)

	    # Tell IMIO where the pixels are.
	    pixoff = (STF_GROUP(stf) - 1) * STF_SZGROUP(stf) + 1
	    call imioff (im, pixoff, compress, blklen)

	default:
	    call imerr (IM_NAME(im), SYS_IMACMODE)
	}

	STF_PFD(stf) = pfd
	IM_PFD(im)   = pfd
end
