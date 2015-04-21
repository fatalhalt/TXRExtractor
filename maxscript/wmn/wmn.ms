/* ----------------------------------------------------------

	Wangan Midnight 3ds Max Model Import Script



	C H A N G E    L O G
	
	April 21, 2015
	- script comments, cleanups, and some changes by nfm aka fatalhalt
	
	April 20, 2015
	- 5th revision by mariokart64n

*/ ----------------------------------------------------------

global f, g, PS3_WANGANM_IMPORTER, mscale = ((1.0/2.54)*100), tex = 1, texn = #()
global impMsh = true, impSkl = false, dumpTex = true, DDSconv = true, guiEnabled = true, clearScene = false, debugMsg = false

struct _geometry (
	position = #(), -- vertices
	uv_coordinate = #(),
	matid = #(),
	matcount = #(),
	face = #()
)

struct _XTD_header (
	fileid = "", -- 3 chars
	vers = 0, -- 1 char
	unk1 = "", -- 4 chars
	offsets = #()
)

-- acts as container that usually stores 2 sub blocks; model data and texture
struct _header (
	fileid = "", -- 3 chars
	filever = 0, -- 1 char
	unk1 = "", -- 4 chars
	unk2 = 0, -- long
	count = 0, -- long, count of sub blocks in current file
	offsets = #(), -- these offsets are relative to a sub block and not the whole file e.g. when XMD contains another XMD
	sizes = #()
)

struct _subheader (
	type = 0, -- short
	string_index = 0, -- short
	size = 0, -- long
	unk2 = 0, -- long
	unk3 = 0 -- long
)

-- this is a table that appears 1 long after "Bp"
struct _filetable (
	unk1 = 0, -- long
	unk2 = 0, -- long, seems to store count, amount of sub blocks
	unk3 = 0, -- long
	offsets = #() -- addresses to sub blocks, which e.g. can store XTD or even nested XMD
)
	
fn RH2LH corrd = (
	[corrd.x,-corrd.z,corrd.y]*mscale
)

fn readBEfloat fstream = (
	bit.intAsFloat (bit.swapBytes (bit.swapBytes (readlong fstream #unsigned) 1 4) 2 3)
)

fn readBElong fstream = (
	bit.swapBytes (bit.swapBytes (readlong fstream #unsigned) 1 4) 2 3
)

fn readBEshort fstream = (
	bit.swapBytes (readshort fstream #unsigned) 1 2
)

fn getpadding num alignment = (
	mod (alignment-(mod num alignment)) alignment
)
	
fn paddstring len instring = (
	local i, str = ""
	instring = instring as string
	if instring.count <=len then (
		for i = 1 to (len-instring.count) do (
			str += "0"
		)
		str = (str+instring)
	) else (
		for i = 1 to len do (
			str+="0";str[i]=instring[i]
		)
	)
	return str
)
	
fn readFixedString bstream fixedLen = (
	local i, str = ""
	for i = 1 to fixedLen do (
		str += bit.intAsChar (ReadByte bstream #unsigned)
	)
	str
)

fn triangle_strip fstream count = (
	global g
	local face_add = 1, matid = 1, vertex_start = 0
	local count, fa, fb, fc , x, y
	local face_flip = true
	local face_reset = true

	x = 0; while x < count do (
		x += 1
		if face_reset == true then (
			x += 2
			face_reset = false
			face_flip = false
			append g.matid matid
			fa = ((readBEshort fstream)-vertex_start) + face_add
			fb = ((readBEshort fstream)-vertex_start) + face_add
			fc = ((readBEshort fstream)-vertex_start) + face_add
			if face_flip == true then (
				append g.face [fa,fc,fb]; face_flip = false
			) else (
				append g.face [fa,fb,fc]; face_flip = true
			)
		) else (
			fa = fb; fb = fc; fc = readBEshort fstream
			if fc < 0xFFFF then (
				fc -= vertex_start
				fc += face_add
				append g.matid matid
				if face_flip == true then (
					append g.face [fa,fc,fb]; face_flip = false
				) else (
					append g.face [fa,fb,fc]; face_flip = true
				)
			) else (
				face_reset = true
			)
		)
	)
)

fn buildObj objname = (
	global g
	local j, msh --,mats = copy g.matcount #nomap
-- 	local faceValid = true
-- 	j = 1; while j < g.face.count and faceValid == true do (
-- 		if g.face[j][1] > g.position.count or g.face[j][1] < 0 do faceValid = false
-- 		if g.face[j][2] > g.position.count or g.face[j][1] < 0 do faceValid = false
-- 		if g.face[j][3] > g.position.count or g.face[j][1] < 0 do faceValid = false
-- 		j += 1
-- 		)
-- 	if faceValid == false do (g.face = #(); print "Face Range Error")
-- 	print g.position.count
-- 	print g.face
	if g.position.count > 0 do (
		msh = mesh vertices:g.position tverts:g.uv_coordinate faces:g.face -- materialIDs:g.matid
		msh.name = objname
		msh.numTVerts = g.uv_coordinate.count
		msh.displayByLayer = false
		msh.backfacecull = on
		buildTVFaces msh

		for j = 1 to g.uv_coordinate.count do setTVert msh j g.uv_coordinate[j]
		for j = 1 to g.face.count do setTVFace msh j g.face[j]
		convertTo msh PolyMeshObject
-- 		if g.matcount.count > 0 do (
-- 		msh.material = multiMaterial numsubs:g.matcount.count
-- 			sort mats
-- 			for j = 1 to g.matcount.count do (
-- 				msh.material.materialList[j].Diffuse = random (color 0 0 0) (color 255 255 255)
-- 				msh.material.materialList[j].diffuseMap = Bitmaptexture fileName:("tex_"+(paddstring 3 (findItem mats g.matcount[j]))+".tga")
-- 				)
-- 			)
		)
	msh
)

fn writeDDSheader fstream texW texH texM texC = (
	local texP = 0, i
	writelong fstream 0x20534444 #unsigned -- File ID
	writelong fstream 0x7C #unsigned -- Header Size
	case texC of ( -- dwFlags
		"DXT1": (
			writelong fstream 0x00081007 #unsigned
			texP = ((texW*texH)/0x02)
		)
		"DXT3": (
			writelong fstream 0x00081007 #unsigned
			texP = (texW*texH)
		)
		"DXT5": (
			writelong fstream 0x00081007 #unsigned
			texP = (texW*texH)
		)
		"ATI1": (
			writelong fstream 0x000A1007 #unsigned
			texP = ((texW*texH)/0x20)
		)
		"ATI2": (
			writelong fstream 0x000A1007 #unsigned
			texP = (texW*texH)
		)
		"P8": (
			writelong fstream 0x000A1007 #unsigned
			texP = ((texW*texH)/0x02)
		)
		"ARGB16": (
			writelong fstream 0x00081007 #unsigned
			texP = (((texW*texH)/0x8)*0x10)
		)
		"ARGB32": (
			writelong fstream 0x00081007 #unsigned
			texP = (((texW*texH)/0x4)*0x10)
		)
	)

	writelong fstream texW #unsigned -- Texture Width
	writelong fstream texH #unsigned -- Texture Height
	writelong fstream texP #unsigned -- Pitch (#of bytes in a single row across the texture)
	writelong fstream 0x00 #unsigned -- Image Depth? Not Used, for Image Volume
	writelong fstream texM #unsigned -- Texture MIP Count
	for i = 1 to 11 do (
		writelong fstream 0x00 #unsigned
	) -- Reserved Space
	writelong fstream 0x20 #unsigned -- Size of PIXEL_FORMAT info, always 32bytes;
	case texC of (
		"DXT1": (
			writelong fstream 0x04;writelong fstream 0x31545844 #unsigned
			writelong fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writelong fstream 0x00001000 #unsigned
		)
		"DXT3": (
			writelong fstream 0x04;writelong fstream 0x33545844 #unsigned
			writelong fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writelong fstream 0x00001000 #unsigned
		)
		"DXT5": (
			writelong fstream 0x04;writelong fstream 0x35545844 #unsigned
			writelong fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writelong fstream 0x00001000 #unsigned
		)
		"ATI1": (
			writelong fstream 0x04;writelong fstream 0x31495441 #unsigned
			writelong fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writelong fstream 0x00401008 #unsigned
		)
		"ATI2": (
			writelong fstream 0x04;writelong fstream 0x32495441 #unsigned
			writelong fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writelong fstream 0x00401008 #unsigned
		)
		"P8": (
			writelong fstream 0x20;writelong fstream 0x20203850 #unsigned
			writelong fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writelong fstream 0x00401008 #unsigned
		)
		"ARGB16": (
			writelong fstream 0x41;writelong fstream 0x00000000 #unsigned
			writelong fstream 0x10;writebyte fstream 0x00;writebyte fstream 0x0F;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0xF0;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x0F;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0xF0;writebyte fstream 0x00
			writebyte fstream 0x00;writelong fstream 0x00001000 #unsigned
		)
		"ARGB32": (
			writelong fstream 0x41;writelong fstream 0x00000000 #unsigned
			writelong fstream 0x20;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0xFF
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0xFF;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0xFF;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00;writebyte fstream 0x00
			writebyte fstream 0xFF;writelong fstream 0x00001000 #unsigned
		)
	)
	for i = 1 to 4 do ( -- Reserved Space for CAPS
		writelong fstream 0x00 #unsigned
	)
)

fn getHeader = (
	global f
	local h = _header(), i = 0, p = ftell f
	h.fileid = readFixedString f 3
	h.filever = readbyte f #unsinged
	h.unk1 = readFixedString f 4
	h.unk2 = readBElong f
	h.count = readBElong f
	h.offsets = (
		for i = 1 to h.count collect (
			readBElong f + p
		)
	)
	fseek f (getpadding (ftell f) 16) #seek_cur
	h.sizes = (
		for i = 1 to h.count collect (
			readBElong f
		)
	)
	fseek f (getpadding (ftell f) 16) #seek_cur
	h
)

-- this function consumes 16 bytes from file's current position
fn getSubHeader = (
	global f
	local s = _subheader()
	
	if debugMsg == true do (format "parsing sub header at 0x%\n" (bit.intAsHex((ftell f) as integer)))
	s.type = readBEshort f
	s.string_index = readBEshort f
	s.size = readBElong f
	s.unk2 = readBElong f
	s.unk3 = readBElong f
	s
)

fn getTXD_header = (
	global f
	local t = _XTD_header(), p = ftell f
	t.fileid = readFixedString f 3
	t.vers = readbyte f #unsigned
	t.unk1 = readFixedString f 4
	t.offsets = (
		for i = 1 to (readlong f #unsigned) collect (
			readlong f #unsigned + p
		)
	)
	t
)

fn dumpGFT spath = (
	global f
	local p = ftell f
	local s, x
	if dumpTex == true do (
		if (readlong f #unsigned) == 0x00000501 and DDSconv == true then (
			readBElong f
			readBElong f
			readBElong f
			data_address = readBElong f + p
			data_size = readBElong f
			fmt = readbyte f #unsigned
			fseek f 0x03 #seek_cur
			readBElong f
			w = readBEshort f
			h = readBEshort f
			fseek f data_address #seek_set
			s = fopen spath "wb"
			writeDDSheader s h w 0 (
				case fmt of (
					0x85: ("ARGB32")
					0x86: ("DXT1")
					0x87: ("DXT3")
					0x88: ("DXT5")
					0xA7: ("DXT3")
					default: (
						format "New DDS Type: 0x%\n" (bit.intAsHex((fmt) as integer))
						"DXT1"
					)
				)
			)
			for x = 1 to data_size do (
				writebyte s (readbyte f #unsigned) #unsigned
			)
			fclose s
		) else (
			fseek f -0x14 #seek_cur
			data_size = readlong f #unsigned - 0x10
			fseek f 0x0C #seek_cur
			s = fopen (spath+".GFT") "wb"
			for x = 1 to data_size do (
				writebyte s (readbyte f #unsigned) #unsigned
			)
			fclose s
		)
	)
)

-- arg1 here is result of getTXD_header()
fn getTXD hdr fpath = (
	global f, tex
	for i = 1 to hdr.offsets.count do (
		fseek f hdr.offsets[i] #seek_set
		size = readlong f #unsigned
		type = readlong f #unsigned
		unk1 = readBEshort f
		unk2 = readBEshort f
		unk3 = readBEshort f
		unk4 = readBEshort f
		if size > 0x10 do (
			if debugMsg == true do print (fpath + "_tex_" + (paddstring 3 i) + ".dds")
			if tex <= texn.count then (
				dumpGFT((getFilenamePath fpath)+texn[tex] + ".dds")
			) else (
				dumpGFT(fpath + "_tex_" + (paddstring 3 tex) + ".dds")
			)
		)
		tex+=1
	)
)

fn getType04 objname = (
	global f
	readBElong f
	readBEshort f
	readBEshort f
	readBElong f
	readBElong f
	
	local pos = [(readBEfloat f),(readBEfloat f),(readBEfloat f)]
	d = dummy()
	d.position = (RH2LH(pos))
	d.name = objname
	d.showLinks = d.showLinksOnly = true
	d
)

fn getType05 h = (
	global f
	local p = ftell f - 16
	fseek f (p+h.size) #seek_set
	for i = 1 to h.unk3 do (
		p = ftell f
		readBEshort f
		readBEshort f
		block_size = readBElong f
		fseek f (p+block_size) #seek_set
	)
)
	
fn getType07 strArray = ( -- materials data
	global f
	local p = ftell f
	readBElong f
	readBElong f
	readBElong f
	count = readBElong f
	
	--if debugMsg == true do (format "Material Sub Block, read 1 long past count, now @ 0x%\n" (bit.intAsHex((ftell f) as integer)))
		
	for i = 1 to count do (
		p = ftell f
		type = readBElong f
		size = readBElong f
		unk1 = readBElong f
		unk2 = readBElong f
		case type of (
			0x02: (
				[(readBEfloat f),(readBEfloat f),(readBEfloat f),(readBEfloat f)]
				[(readBEfloat f),(readBEfloat f),(readBEfloat f),(readBEfloat f)]
				[(readBEfloat f),(readBEfloat f),(readBEfloat f),(readBEfloat f)]
				[(readBEfloat f),(readBEfloat f),(readBEfloat f),(readBEfloat f)]
				[(readBEfloat f),(readBEfloat f),(readBEfloat f),(readBEfloat f)]
				[(readBEfloat f),(readBEfloat f),(readBEfloat f),(readBEfloat f)]
				[(readBEfloat f),(readBEfloat f),(readBEfloat f),(readBEfloat f)]
			)
			0x03: (
				readBElong f
				readBElong f
				readBElong f
				readBElong f
				
				--print strArray[idx]
			)
			0x09: (
				readBElong f
				readBElong f
				readBElong f
				readBElong f
			)
			0x0B: (
			)
			default : (
				--if debugMsg == true do (format "Material Sub Block, Unknown Material Type @ 0x%\n" (bit.intAsHex((ftell f) as integer)))
			)
		)
		fseek f (p + size) #seek_set
	)
)

fn getType08 objname = ( -- geomety data
	global f, g = _geometry()
	local p = ftell f, getPos
	
	unk01=readBElong f
	unk02=readBElong f
	unk03=readBElong f
	unk04=readBElong f
	
	bmin = [(readBEfloat f),(readBEfloat f),(readBEfloat f),(readBEfloat f)]
	bmax = [(readBEfloat f),(readBEfloat f),(readBEfloat f),(readBEfloat f)]
	
	unk05=readBElong f
	unk06=readBElong f
	count1 = readBElong f
	count2 = readBElong f
	
	unk07=readBElong f
	unk08=readBElong f
	unk09=readBElong f
	unk10=readBElong f
	
-- 	if debugMsg == true do (
-- 		format "Unknowns[%]:\t % % % % % % % % % %\n" \
-- 			count1 unk01 unk02 unk03 unk04 unk05 \
-- 			unk06 unk07 unk08 unk09 unk10
-- 		)
	
	for i = 1 to count2 do ( -- e.g. you would loop to grab faces then vertices and so on, see case statement
		getPos = ftell f
		
		readBElong f -- 0x000A0000
		block_size = readBElong f
		comp = readBElong f
		datatype = readBElong f
		
		readBElong f
		count = readBElong f -- e.g. number of faces or vertices
		readBElong f
		readBElong f
		
		case comp of (
			0x00: ( -- face
				triangle_strip f count
			)
			0x02: ( -- position
				for i = 1 to count do (
					append g.position (RH2LH([(readBEfloat f),(readBEfloat f),(readBEfloat f)]))
				)
			)
			0x03: ( -- colours
			)
			0x04: ( -- normals
			)
			0x05: ( -- UVs
				for i = 1 to count do (
					append g.uv_coordinate ([(readBEfloat f),1-(readBEfloat f),0])
				)
			)
			0x0B: ( -- Bone Indices
-- 				for i = 1 to count do (
-- 					b1 = readBEfloat f
-- 					b2 = readBEfloat f
-- 					b3 = readBEfloat f
-- 					b4 = readBEfloat f
-- 				)
			)
			0x0C: ( -- Bone Weights
-- 				for i = 1 to count do (
-- 					b1 = readBEfloat f
-- 					b2 = readBEfloat f
-- 					b3 = readBEfloat f
-- 					b4 = readBEfloat f
-- 				)
			)
			default: (
				format "Error Vertex Format Unsupported [%] @ 0x%\n" \
					comp (bit.intAsHex((getPos) as integer))
			)
		)
		fseek f (getPos + block_size) #seek_set
	)

	--print g.uv_coordinate.count
	if g.uv_coordinate.count < g.position.count do (
		for i = 1 to (g.position.count - g.uv_coordinate.count) do (
			append g.uv_coordinate [0,0,0]
		)
	)
		
	buildObj(objname)
)

fn getType21 = ( -- string data
	global f
	readstring f
)

-- called from getStuff()
fn getStuffTable pos = (
	global f
	local t = _filetable()
	t.unk1 = readBElong f
	t.unk2 = readBElong f
	t.unk3 = readBElong f
	t.offsets = (
		for i = 1 to t.unk2 collect (
			readBElong f + pos
		)
	)
	t
)

-- this function is called when 0x0 long magic is encounter in XMD file container
-- arg1's position usually will be at "Bp" section here
fn getStuff pos = (
	global f
	local p = ftell f, strArray = #(), boneArray = #(), subHeaderArray = #()
	fseek f 0x80 #seek_cur -- FIX ME, NOTICE THAT IT SEEK EXTRA 80h FROM CURR POS
	
	-- HEADER HERE DESCRIBES COUNTS FOR DATA BELOW
	check = readlong f #unsigned
	if check == 0x00007042 or check == 0x0000F041 or check == 0x0000C041 then ( -- check for "Bp" section
		table = getStuffTable(pos)
		
		-- seek to all sub blocks and parse their header solely to prefetch string array that will be used in next loop
		for i = 1 to table.unk2 do (
			fseek f table.offsets[i] #seek_set
			sb = getSubHeader()
			append subHeaderArray sb
			if sb.type == 0x15 do (
				append strArray (getType21())
			)
		)

		for i = 1 to table.unk2 do (
			fseek f (table.offsets[i] + 16) #seek_set
			sb = subHeaderArray[i]
			block_name = ""
			if debugMsg == true do block_name += (i as string) + " "
			if sb.string_index > 0 and sb.string_index <= strArray.count do (
				block_name += strArray[(sb.string_index)] -- creates block names such as "1 Detail" or  "3 mat_sitamichi00_sh"
			)
			
			case sb.type of (
				0x04: ( -- matrix?
					if debugMsg == true do (format "Matrix? @ 0x%\n" (bit.intAsHex((table.offsets[i]) as integer)))
					if impSkl == true do (
						append boneArray (getType04(block_name))
						if sb.unk2 > 0 and sb.unk2 <= boneArray.count do (
							try (
								boneArray[(boneArray.count)].parent = boneArray[(sb.unk2)]
							)
							catch (
								if debugMsg == true do (
									format "Illegal parent, possibly same node or ancestor node [Index:%(%) Parent:%]\n" \
										boneArray.count sb.unk3 sb.unk2
								)
							)
						)
					)
				)
				0x05: ( -- bounding box
					if debugMsg == true do (format "Bounding Box? @ 0x%\n" (bit.intAsHex((table.offsets[i]) as integer)))
					getType05(sb)
				)
				0x07: ( -- materials
					if debugMsg == true do (format "Material @ 0x%\n\tName: %\n" (bit.intAsHex((table.offsets[i]) as integer)) block_name)
					getType07(strArray)
				)
				0x08: ( -- geometry
					if debugMsg == true do (format "Geometry @ 0x%\n" (bit.intAsHex((table.offsets[i]) as integer)))
					if impMsh == true do (
						getType08(block_name)
					)
				)
				0x0C: ( -- texture names?
					if debugMsg == true do (format "Textures ? @ 0x%\n\tName: %\n" (bit.intAsHex((table.offsets[i]) as integer)) block_name)
					append texn block_name
				)
				0x11: ( -- IK Bone
					if debugMsg == true do (format "IK Bone @ 0x%\n\tName: %\n" (bit.intAsHex((table.offsets[i]) as integer)) block_name)
				)
				0x15: ( -- string data
				)
				default: (
					format "SubBlock Not Supported [%] @ 0x%\n" \
						sb.type (bit.intAsHex((table.offsets[i]) as integer))
				)
			)

		) -- end of sub block loop
	) else (
		format "Error: Failed to seek to table\n"
	)
	if debugMsg == true do (
		format "String Table\n"
		for i = 1 to strArray.count do (
			format "%:\t%\n" i strArray[i]
		)
	)
)	

	
-- this fn reads first long of a file called magic and decides what to make of it
-- GTF stores multiple headerless DDS image, some even are 8888:32bit
fn readBinary filen = (
	global f
	local magic = readlong f #unsigned
	fseek f -4 #seek_cur
	case magic of (
		0x01444D58: ( -- XMD (Xtreme Model Data)
			hdr = getHeader()
			for d = 1 to hdr.count do (
				-- seeks to an offset, grabs long and seeks back a long
				fseek f hdr.offsets[d] #seek_set
				filetype = readlong f #unsigned
				fseek f hdr.offsets[d] #seek_set
				case filetype of (
					0x00000000: ( -- usaully means we hit the 2 longs before X3D0037 section
						getStuff(hdr.offsets[d])
					)
					0x01444D58: ( -- nested XMD (Xtreme Model Data)
						readBinary(filen)
					)
					0x00445458: ( -- XTD (Xtreme Texture Data)
						--getTXD( getTXD_header() )((getFilenamePath filen)+(getFilenameFile filen))
						readBinary(filen)
					)
					default: (
						format "Error: New Block Type [%] @ Address: 0x%\n" \
							filetype (bit.intAsHex((hdr.offsets[d]) as integer))
					)
				)
			)
		)
		0x00445458: ( -- XTD (Xtreme Texture Data)
			getTXD(getTXD_header())((getFilenamePath filen)+(getFilenameFile filen))
		)
		0x00000501: ( -- GTF
			dumpGFT((getFilenamePath filen)+(getFilenameFile filen)+"_tex_001.dds")
		)
	)
)

fn openFilen filen = (
	global f
	format "opening file %\n" filen
	if filen != undefined and doesFileExist filen == true then (
		try (fclose f) catch(gc())
		f = fopen filen "rb"
		if clearScene == true do (delete $*)

		readBinary(filen)

		if debugMsg == true do (format "last read @ 0x%\n" (bit.intAsHex((ftell f) as integer)))
		fclose f
		return true
	) else (
		format "failed to open %\n" filen
		return false
	)
)


-- code execution starts here, first we clear listener window
clearlistener()

-- globals below are freely accessible
if guiEnabled == false then (
	local filen = ""

	--filenames = stringstream ""
	--format "D:\\MaxScript\\C1\\AREA_C1_ROAD_MDL_000.GRID\n" to:filenames
	--for i = 1 to 2 do (
	--	format "D:\\MaxScript\\C1\\AREA_C1_ROAD_MDL_%%\n" (formattedPrint i format:".3d" as string)  ".GRID" to:filenames
	--)
	--seek filenames 0

	--for i = 1 to 1 do (
	--	filen = readLine filenames
	--	openFilen(filen)
	--)
	openFilen("D:\\MaxScript\\C1\\AREA_11GO_BUIL_CUT_11GO_WAN_013.GRID")
) else (
	try (destroydialog PS3_WANGANM_IMPORTER) catch()
	rollout PS3_WANGANM_IMPORTER "Wangan Midnight" (
		group "Main" (
			button btn1 "IMPORT" width:65 height:31 align:#center
			label ls0 ""  -- spacer
			checkbox chk1 "Clear Scene     " checked:true align:#center
			checkbox chk3 "Import Mesh    " checked:true align:#center
			checkbox chk4 "Import Bones   " checked:false align:#center
			checkbox chk2 "Dump Textures" checked:false align:#center
			checkbox chk5 "Convert to DDS" checked:false align:#center
		)
		group "About" (
			hyperLink lb5 "Author:  mariokart64n," address:"mailto:mario_kart64n@hotmail.com"
			label lb8 "              nfm aka fatalhalt" align:#left
			label lb3 "Date:     April 2015" align:#left
		)
		on chk1 changed theState do (
			clearScene = theState
		)
		on chk2 changed theState do (
			dumpTex = theState
		)
		on chk3 changed theState do (
			impMsh = theState
		)
		on chk4 changed theState do (
			impSkl = theState
		)
		on chk5 changed theState do (
			DDSconv = theState
		)
		on PS3_WANGANM_IMPORTER open do (
			chk1.checked = clearScene
			chk2.checked = dumpTex
			chk3.checked = impMsh
			chk4.checked = impSkl
			chk5.checked = DDSconv
		)
		on btn1 pressed do (
			local filen_ = GetOpenFileName \
			caption:"Select GRID File" \
			types: "Wangan Midnight files (*.*)|*.*|"

			if openFilen(filen_) == true do (
				messagebox "Done!"
				if debugMsg == true do (print texn)
			)
		)
	)
	createdialog PS3_WANGANM_IMPORTER
)
