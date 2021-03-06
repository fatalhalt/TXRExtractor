/* ----------------------------------------------------------

	Wangan Midnight 3ds Max Model Import Script



	C H A N G E    L O G

	May 2015 to 2017?
    - support generating assetto corsa .ini shader file for easier map import, 'assettoCorsaWriteConfig' variable must be set to 'true'
	
	April 21~25, 2015
	- figured out how geometry and materials are linked, and how materials link to textures
	- implemented creation of materials with hooked up diffuse, specular, reflection, and opacity maps
	- and many more small things that were needed to get this far, many days spent in hex editor and maxscript
		by nfm aka fatalhalt
	
	April 21, 2015
	- script comments, cleanups, and some changes by nfm aka fatalhalt
	
	April 20, 2015
	- 5th revision by mariokart64n


	Original forum thread: http://forum.xentax.com/viewtopic.php?f=16&t=12775
	
	Notes;
	- GTF textures, it appears that 00.GTF are normal maps, 01.GTF are diffuse, 02.GTF can be anything--opacity, specular, reflection, e.g. if material has only 1 bitmap
	and it of 02.GTF it makes me conclude that it is a single opacity map meant to be alpha blended/test
	- some materials point to 03.GTF but there's no such file, usually this is found on materials with _light_ name in it e.g. shuto tunnel has these materials
	- geo_v_Xenon1 and alike is unknown geo, it has no material, it resembles outline of the roads, maybe used by game engine for car to stay on road in case geo doesn't load fast enough
	- some geo with 2 bitmaps, where 1st is diffuse have the 2nd bitmap very dark, e.g. overhead hw signs, but also geo like road has 2nd texture similar to first but brighter--specular?
	- geo such _BUIL_CUT_ contains many reflection maps, e.g. night time light reflections off of buildings

*/ ----------------------------------------------------------

global f, g, PS3_WANGANM_IMPORTER, m = #(), t = #(), currentFilen = "", offToXTDofCurrentXMD = 0, didPrepopulateT = false
global impMsh = true, impSkl = false, dumpTex = false, DDSconv = true, guiEnabled = false, clearScene = false, debugMsg = false
global handledTheseTextures = #(), opacityBitmapList = #(), specularBitmapList = #(), reflectionBitmapList = #(), normalBitmapList = #(), noTextureMaterialList = #(), noMaterialList = #()
global mscale = 1.0 --, mscale = ((1.0/2.54)*100)
global printTextureStats = false, passAllTexturesAsDiffuse = false

global assettoCorsaWriteConfig = true, acConfig, assettoCorsaConfigPath = "C:\\", assettoCorsaConfigFname = "map.fbx", acMatCount = 0

struct _geometry (
	position = #(), -- vertices
	uv_coordinate = #(),
	matid = 0, -- seems like each geometry has 1 material, matid seems to map to subheader's unk3 member
	submatcount = #(), 
	face = #()
)

struct _matbitmap (
	name = "", -- e.g. tx_name_0, tx_name_1, or ref_name
	index = 0 -- index to texture 
)

struct _material ( -- geometry should reference this somehow
	mat_str_index = 0, -- material name
	submatcount = 0, -- amount of sub materials like diffuse map, rough map, bump map

	--  tes_ren
	--  use_light                 bool
	--  shadow_map              bool?
	--  reflect_map             bool?
	--  EnableVertexColor    bool
	--  mat_blend
	--  Specular                  3~4 floats?
	--  Rough                      3~4 floats?
	--  Enable_tx_name_0   bool
	--  tx_blend_0
	--  tx_color_0             saw 1.0f 0.0f 0.0f, what's this?
	--  Enable_tx_name_1   bool
	--  tx_blend_1
	--  tx_color_1
	--  EnableBumpTexture  bool
	--  Enable_ref_name     bool
	--  reflectivity            3~4 floats?
	--  sys_zkeep               bool?
	--  depth_type             bool?
	
	depth_type = 0, -- it seems that it's 1 when a texture is an opacity map
	mat_bitmaps = #()
)

-- there will be as many of these structs as there are offsets to textures in XTD sub block!
struct _texture (
	texname = "", -- name from sring table
	tex_path = "", -- full path to texture on disk
	tex_str_index = 0,
	offset_nth_in_xtd = 0
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
	if instring.count <= len then (
		for i = 1 to (len-instring.count) do (
			str += "0"
		)
		str = (str+instring)
	) else (
		for i = 1 to len do (
			str += "0"; str[i] = instring[i]
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

fn readNullStr bstream = (
	local str = ""
	while true do (
		str0 = ReadByte bstream #unsigned
		if str0 == 0 then exit
		str += bit.intAsChar str0
	)
	str
)


fn assettoCorsaAlphaTestConfig matName texName = (
	writestring acConfig (
		"\r\n[MATERIAL_" + acMatCount as string + "]\r\n" +
		"NAME=" + matName + "\r\n" +
		"SHADER=ksPerPixel\r\n" +
		"ALPHABLEND=0\r\n" +
		"ALPHATEST=1\r\n" +
		"DEPTHMODE=0\r\n" +
		"VARCOUNT=6\r\n" +
		"VAR_0_NAME=ksAmbient\r\n" +
		"VAR_0_FLOAT1=0.5\r\n" +
		"VAR_0_FLOAT2=0,0\r\n" +
		"VAR_0_FLOAT3=0,0,0\r\n" +
		"VAR_0_FLOAT4=0,0,0,0\r\n" +
		"VAR_1_NAME=ksDiffuse\r\n" +
		"VAR_1_FLOAT1=0.4\r\n" +
		"VAR_1_FLOAT2=0,0\r\n" +
		"VAR_1_FLOAT3=0,0,0\r\n" +
		"VAR_1_FLOAT4=0,0,0,0\r\n" +
		"VAR_2_NAME=ksSpecular\r\n" +
		"VAR_2_FLOAT1=0.2\r\n" +
		"VAR_2_FLOAT2=0,0\r\n" +
		"VAR_2_FLOAT3=0,0,0\r\n" +
		"VAR_2_FLOAT4=0,0,0,0\r\n" +
		"VAR_3_NAME=ksSpecularEXP\r\n" +
		"VAR_3_FLOAT1=30\r\n" +
		"VAR_3_FLOAT2=0,0\r\n" +
		"VAR_3_FLOAT3=0,0,0\r\n" +
		"VAR_3_FLOAT4=0,0,0,0\r\n" +
		"VAR_4_NAME=ksEmissive\r\n" +
		"VAR_4_FLOAT1=0\r\n" +
		"VAR_4_FLOAT2=0,0\r\n" +
		"VAR_4_FLOAT3=0,0,0\r\n" +
		"VAR_4_FLOAT4=0,0,0,0\r\n" +
		"VAR_5_NAME=ksAlphaRef\r\n" +
		"VAR_5_FLOAT1=0\r\n" +
		"VAR_5_FLOAT2=0,0\r\n" +
		"VAR_5_FLOAT3=0,0,0\r\n" +
		"VAR_5_FLOAT4=0,0,0,0\r\n" +
		"RESCOUNT=1\r\n" +
		"RES_0_NAME=txDiffuse\r\n" +
		"RES_0_SLOT=0\r\n" +
		"RES_0_TEXTURE=" + texName + "\r\n"
	)
	
	acMatCount += 1
)

fn assettoCorsaNormalMapConfig matName diftexName nrmlTexName = (
	writestring acConfig (
		"\r\n[MATERIAL_" + acMatCount as string + "]\r\n" +
		"NAME=" + matName + "\r\n" +
		"SHADER=ksPerPixelNM\r\n" +
		"ALPHABLEND=0\r\n" +
		"ALPHATEST=0\r\n" +
		"DEPTHMODE=0\r\n" +
		"VARCOUNT=12\r\n" +
		"VAR_0_NAME=ksAmbient\r\n" +
		"VAR_0_FLOAT1=0.5\r\n" +
		"VAR_0_FLOAT2=0,0\r\n" +
		"VAR_0_FLOAT3=0,0,0\r\n" +
		"VAR_0_FLOAT4=0,0,0,0\r\n" +
		"VAR_1_NAME=ksDiffuse\r\n" +
		"VAR_1_FLOAT1=0.4\r\n" +
		"VAR_1_FLOAT2=0,0\r\n" +
		"VAR_1_FLOAT3=0,0,0\r\n" +
		"VAR_1_FLOAT4=0,0,0,0\r\n" +
		"VAR_2_NAME=ksSpecular\r\n" +
		"VAR_2_FLOAT1=0.2\r\n" +
		"VAR_2_FLOAT2=0,0\r\n" +
		"VAR_2_FLOAT3=0,0,0\r\n" +
		"VAR_2_FLOAT4=0,0,0,0\r\n" +
		"VAR_3_NAME=ksSpecularEXP\r\n" +
		"VAR_3_FLOAT1=30\r\n" +
		"VAR_3_FLOAT2=0,0\r\n" +
		"VAR_3_FLOAT3=0,0,0\r\n" +
		"VAR_3_FLOAT4=0,0,0,0\r\n" +
		"VAR_4_NAME=ksEmissive\r\n" +
		"VAR_4_FLOAT1=0\r\n" +
		"VAR_4_FLOAT2=0,0\r\n" +
		"VAR_4_FLOAT3=0,0,0\r\n" +
		"VAR_4_FLOAT4=0,0,0,0\r\n" +
		"VAR_5_NAME=ksAlphaRef\r\n" +
		"VAR_5_FLOAT1=0\r\n" +
		"VAR_5_FLOAT2=0,0\r\n" +
		"VAR_5_FLOAT3=0,0,0\r\n" +
		"VAR_5_FLOAT4=0,0,0,0\r\n" +
		"VAR_6_NAME=fresnelC\r\n" +
		"VAR_6_FLOAT1=0\r\n" +
		"VAR_6_FLOAT2=0,0\r\n" +
		"VAR_6_FLOAT3=0,0,0\r\n" +
		"VAR_6_FLOAT4=0,0,0,0\r\n" +
		"VAR_7_NAME=fresnelEXP\r\n" +
		"VAR_7_FLOAT1=0\r\n" +
		"VAR_7_FLOAT2=0,0\r\n" +
		"VAR_7_FLOAT3=0,0,0\r\n" +
		"VAR_7_FLOAT4=0,0,0,0\r\n" +
		"VAR_8_NAME=nmObjectSpace\r\n" +
		"VAR_8_FLOAT1=0\r\n" +
		"VAR_8_FLOAT2=0,0\r\n" +
		"VAR_8_FLOAT3=0,0,0\r\n" +
		"VAR_8_FLOAT4=0,0,0,0\r\n" +
		"VAR_9_NAME=isAdditive\r\n" +
		"VAR_9_FLOAT1=0\r\n" +
		"VAR_9_FLOAT2=0,0\r\n" +
		"VAR_9_FLOAT3=0,0,0\r\n" +
		"VAR_9_FLOAT4=0,0,0,0\r\n" +
		"VAR_10_NAME=fresnelMaxLevel\r\n" +
		"VAR_10_FLOAT1=0\r\n" +
		"VAR_10_FLOAT2=0,0\r\n" +
		"VAR_10_FLOAT3=0,0,0\r\n" +
		"VAR_10_FLOAT4=0,0,0,0\r\n" +
		"VAR_11_NAME=boh\r\n" +
		"VAR_11_FLOAT1=0\r\n" +
		"VAR_11_FLOAT2=0,0\r\n" +
		"VAR_11_FLOAT3=0,0,0\r\n" +
		"VAR_11_FLOAT4=0,0,0,0\r\n" +
		"RESCOUNT=2\r\n" +
		"RES_0_NAME=txDiffuse\r\n" +
		"RES_0_SLOT=0\r\n" +
		"RES_0_TEXTURE=" + diftexName + "\r\n" +
		"RES_1_NAME=txNormal\r\n" +
		"RES_1_SLOT=1\r\n" +
		"RES_1_TEXTURE=" + nrmlTexName + "\r\n"
	)
	
	acMatCount += 1
)

fn assettoCorsaDiffuseMapConfig matName diftexName = (
	writestring acConfig (
		"\r\n[MATERIAL_" + acMatCount as string + "]\r\n" +
		"NAME=" + matName + "\r\n" +
		"SHADER=ksPerPixel\r\n" +
		"ALPHABLEND=0\r\n" +
		"ALPHATEST=0\r\n" +
		"DEPTHMODE=0\r\n" +
		"VARCOUNT=6\r\n" +
		"VAR_0_NAME=ksAmbient\r\n" +
		"VAR_0_FLOAT1=0.5\r\n" +
		"VAR_0_FLOAT2=0,0\r\n" +
		"VAR_0_FLOAT3=0,0,0\r\n" +
		"VAR_0_FLOAT4=0,0,0,0\r\n" +
		"VAR_1_NAME=ksDiffuse\r\n" +
		"VAR_1_FLOAT1=0.4\r\n" +
		"VAR_1_FLOAT2=0,0\r\n" +
		"VAR_1_FLOAT3=0,0,0\r\n" +
		"VAR_1_FLOAT4=0,0,0,0\r\n" +
		"VAR_2_NAME=ksSpecular\r\n" +
		"VAR_2_FLOAT1=0.2\r\n" +
		"VAR_2_FLOAT2=0,0\r\n" +
		"VAR_2_FLOAT3=0,0,0\r\n" +
		"VAR_2_FLOAT4=0,0,0,0\r\n" +
		"VAR_3_NAME=ksSpecularEXP\r\n" +
		"VAR_3_FLOAT1=30\r\n" +
		"VAR_3_FLOAT2=0,0\r\n" +
		"VAR_3_FLOAT3=0,0,0\r\n" +
		"VAR_3_FLOAT4=0,0,0,0\r\n" +
		"VAR_4_NAME=ksEmissive\r\n" +
		"VAR_4_FLOAT1=0\r\n" +
		"VAR_4_FLOAT2=0,0\r\n" +
		"VAR_4_FLOAT3=0,0,0\r\n" +
		"VAR_4_FLOAT4=0,0,0,0\r\n" +
		"VAR_5_NAME=ksAlphaRef\r\n" +
		"VAR_5_FLOAT1=0\r\n" +
		"VAR_5_FLOAT2=0,0\r\n" +
		"VAR_5_FLOAT3=0,0,0\r\n" +
		"VAR_5_FLOAT4=0,0,0,0\r\n" +
		"RESCOUNT=1\r\n" +
		"RES_0_NAME=txDiffuse\r\n" +
		"RES_0_SLOT=0\r\n" +
		"RES_0_TEXTURE=" + diftexName + "\r\n"
	)
	
	acMatCount += 1
)

fn assettoCorsaConfigClose = (
	--fflush acConfig
	--fseek acConfig 0 #seek_set
	writestring acConfig ("\r\n[HEADER]\r\nVERSION=3\r\n\r\n[MATERIAL_LIST]\r\nCOUNT=" + acMatCount as string + "\r\n")

	fclose acConfig
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

fn triangle_strip fstream count matid = (
	global g
	local face_add = 1, vertex_start = 0
	local count, fa, fb, fc , x, y
	local face_flip = true
	local face_reset = true

	x = 0; while x < count do (
		x += 1
		if face_reset == true then (
			x += 2
			face_reset = false
			face_flip = false
			g.matid = matid
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
				g.matid = matid
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

fn buildObj objname strArray = (
	global f, g, m, t, offToXTDofCurrentXMD, getTXD, didPrepopulateT
	local j, prevTexName, msh --,mats = copy g.matcount #nomap
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

		-- populate items in t with texture names, FIXME (done): this really has to be done only once, meshes following this one should be good to go
		if didPrepopulateT == false do (
			if debugMsg == true do (format "\tbuildObj(): seeking f to 0x%\n" (bit.intAsHex offToXTDofCurrentXMD))
			fseek f offToXTDofCurrentXMD #seek_set -- fucking bitch ass isn't populated yet here, and there's no easy way to do it
			getTXD (getTXD_header()) ((getFilenamePath currentFilen)+(getFilenameFile currentFilen)) false
			didPrepopulateT = true
		)
		if debugMsg == true do (format "\tbuildObj(): m count: %, t count: %, mesh matid: %\n" m.count t.count (g.matid+1))


		if m.count > 0 and g.matid < m.count then ( -- some geometry like e.g. "ufj_01.component[5]" has no material, FIXME: some meshes have matid beyond m array!?
			-- create material
			mat_name = strArray[m[g.matid+1].mat_str_index]
			matr = standardmaterial name:mat_name
			mat_index_to_tx = 0 -- mesh's material often has a bitmap texture in form of a index to global texture array
			if debugMsg == true do (format "\tmaterial name: %, mat_bitmaps count: %\n" mat_name m[g.matid+1].mat_bitmaps.count)

			-- check if there are any bitmaps aka textures
			bitmap_count = m[g.matid+1].mat_bitmaps.count
			assert (bitmap_count <= 3) message: "m has more than 3 textures!" options:#(#dialog)

			if bitmap_count > 0 then ( -- code below will create components such as diffuse, specular, or normal map for given material
				for k = 1 to bitmap_count do (
					mat_index_to_tx = m[g.matid+1].mat_bitmaps[k].index
					mat_tx_name = t[mat_index_to_tx+1].texname
					mat_tx_path = t[mat_index_to_tx+1].tex_path
					if debugMsg == true do (format "\ttexname %: %, texpath: %\n"  k mat_tx_name mat_tx_path)
					
					if passAllTexturesAsDiffuse == false then (
						-- FIXME: seriously, turn below multiple if statements info if else
						if findString mat_tx_name "file0" != undefined do ( -- diffuse or opacity
							if m[g.matid+1].depth_type == 0x01 and bitmap_count == 1 then ( -- i assume material with 1 bitmap here is opacity
								-- FIXME: there are some false positves, some textures come out to have opacity when they shouldn't have
								matr.opacityMap = bitmaptexture name:mat_tx_name
								append handledTheseTextures mat_tx_name
								matr.opacityMap.filename = mat_tx_path
								append opacityBitmapList (objname + ": " + mat_name + " -- " + mat_tx_name + " texture")
							
								if bitmap_count == 1 and assettoCorsaWriteConfig == true do (
									assettoCorsaAlphaTestConfig mat_name ((getFilenameFile mat_tx_path) + ".dds")
								)
							
								prevTexName = mat_tx_path
								continue
							) else (
								matr.diffusemap = bitmaptexture name:mat_tx_name
								append handledTheseTextures mat_tx_name
								matr.diffusemap.filename = mat_tx_path
								--showtexturemap matr matr.diffusemap true

								if bitmap_count == 1 and assettoCorsaWriteConfig == true do (
									assettoCorsaDiffuseMapConfig mat_name ((getFilenameFile mat_tx_path) + ".dds")
								)
							
								prevTexName = mat_tx_path
								continue
							)
						)
						
						if findString mat_tx_name "reffile" != undefined do ( -- reflection map?
							matr.reflectionMap = bitmaptexture name:mat_tx_name
							append handledTheseTextures mat_tx_name
							matr.reflectionMap.filename = mat_tx_path
							append reflectionBitmapList (objname + ": " + mat_name + " -- " + mat_tx_name + " texture")

							if bitmap_count == 2 and k == 2 and assettoCorsaWriteConfig == true do (
								assettoCorsaDiffuseMapConfig mat_name ((getFilenameFile prevTexName) + ".dds")
							)

							prevTexName = mat_tx_path
							continue
						)

						if findString mat_tx_name "nrmfile" != undefined do ( -- normal map
							normalmap_bitmap = bitmaptexture name:mat_tx_name
							append handledTheseTextures mat_tx_name
							normalmap_bitmap.filename = mat_tx_path
							normalmap = Normal_Bump name:mat_tx_name
							normalmap.normal_map = normalmap_bitmap
							matr.bumpMap = normalmap
							append normalBitmapList (objname + ": " + mat_name + " -- " + mat_tx_name + " texture")
							--showtexturemap matr matr.bumpMap true -- actually there's no such thing for bump
							
							if bitmap_count == 2 and assettoCorsaWriteConfig == true and k == 2 do ( -- pretty good guess, we have 2 texures, 1st is diffuse and 2nd normal?
								assettoCorsaNormalMapConfig mat_name ((getFilenameFile prevTexName) + ".dds") ((getFilenameFile mat_tx_path) + ".dds") -- hopefully prevTexName was the name of diffuse texture or we're fucked
							)

							prevTexName = mat_tx_path
							continue
						)
						
						-- the more i looked it seems this is some misc specialty/extra texture
						if findString mat_tx_name "file1" != undefined do ( -- specular??? everytime i checked this texture it looked same as diffuse but more shiny
							matr.specularMap = bitmaptexture name:mat_tx_name -- specular maps are used mostly on metal objects?
							append handledTheseTextures mat_tx_name
							matr.specularMap.filename = mat_tx_path
							append specularBitmapList (objname + ": " + mat_name + " -- " + mat_tx_name + " texture")
							--showtexturemap matr matr.specularMap true -- this will unshow diffuse channel, hmm, maybe that's how 3ds works, specular will get shown during rendering
							
							-- added this to catch cases such as shuto overhead signs, at this point we know 2nd tex is not nrm or ref, the latter or statement hopefully catches the buildings
							if ((bitmap_count == 2 and k == 2 and assettoCorsaWriteConfig == true) or (bitmap_count == 3 and k == 2 and assettoCorsaWriteConfig == true)) do (
								assettoCorsaDiffuseMapConfig mat_name ((getFilenameFile prevTexName) + ".dds")
							)
							
							prevTexName = mat_tx_path
							continue
						)
						
						-- if we get here we'll just use diffuse
						matr.diffusemap = bitmaptexture name:mat_tx_name
						append handledTheseTextures mat_tx_name
						matr.diffusemap.filename = mat_tx_path

					) else ( -- make all textures as diffuse
						if k == 1 do (
							matr.diffusemap = bitmaptexture name:mat_tx_name
							append handledTheseTextures mat_tx_name
							matr.diffusemap.filename = mat_tx_path

							if bitmap_count == 1 and assettoCorsaWriteConfig == true do (
								assettoCorsaDiffuseMapConfig mat_name ((getFilenameFile mat_tx_path) + ".dds")
							)
							prevTexName = mat_tx_path
						)
					)
					
					-- FIXME: there are some texture names like gt_sky* or *file2, *file2b, *file3 *file4...
				)
			) else ( -- material has no texure
				append noTextureMaterialList mat_name
			)

			-- done
			showTextureMap matr true
			msh.material = matr
		) else ( -- geometry with no material, pain in butt?
			append noMaterialList objname
		)
		
		convertTo msh PolyMeshObject

-- 		if g.matcount.count > 0 do (
-- 		msh.material = multiMaterial numsubs:g.matcount.count
-- 			sort mats
-- 			for j = 1 to g.matcount.count do (
-- 				msh.material.materialList[j].Diffuse = random (color 0 0 0) (color 255 255 255)
-- 				msh.material.materialList[j].diffuseMap = Bitmaptexture fileName:("tex_"+(paddstring 3 (findItem mats g.matcount[j]))+".tga")
-- 			)
-- 		)
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
			writelong fstream 0x04; writelong fstream 0x31545844 #unsigned
			writelong fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writelong fstream 0x00001000 #unsigned
		)
		"DXT3": (
			writelong fstream 0x04; writelong fstream 0x33545844 #unsigned
			writelong fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writelong fstream 0x00001000 #unsigned
		)
		"DXT5": (
			writelong fstream 0x04; writelong fstream 0x35545844 #unsigned
			writelong fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writelong fstream 0x00001000 #unsigned
		)
		"ATI1": (
			writelong fstream 0x04; writelong fstream 0x31495441 #unsigned
			writelong fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writelong fstream 0x00401008 #unsigned
		)
		"ATI2": (
			writelong fstream 0x04; writelong fstream 0x32495441 #unsigned
			writelong fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writelong fstream 0x00401008 #unsigned
		)
		"P8": (
			writelong fstream 0x20; writelong fstream 0x20203850 #unsigned
			writelong fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writelong fstream 0x00401008 #unsigned
		)
		"ARGB16": (
			writelong fstream 0x41; writelong fstream 0x00000000 #unsigned
			writelong fstream 0x10; writebyte fstream 0x00; writebyte fstream 0x0F; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0xF0; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x0F; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0xF0; writebyte fstream 0x00
			writebyte fstream 0x00; writelong fstream 0x00001000 #unsigned
		)
		"ARGB32": (
			writelong fstream 0x41; writelong fstream 0x00000000 #unsigned
			writelong fstream 0x20; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0xFF
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0xFF; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0xFF; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00; writebyte fstream 0x00
			writebyte fstream 0xFF; writelong fstream 0x00001000 #unsigned
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
	s.type = readBEshort f
	s.string_index = readBEshort f
	if debugMsg == true do (format "parsing sub header at 0x%, type: %\n" (bit.intAsHex(((ftell f)-4) as integer)) s.type)
	s.size = readBElong f
	s.unk2 = readBElong f
	s.unk3 = readBElong f
	s
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
						format "new DDS type: 0x%\n" (bit.intAsHex((fmt) as integer))
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
		format "dumped file %\n" spath
	)
)

-- arg1 here is result of getTXD_header()
fn getTXD hdr fpath doDump = (
	global f, t
	if debugMsg == true do (format "\nparsing XTD at 0x%\n\ttexture struct has % items, TXD header contains % offsets, doDump = %\n" \
	(bit.intAsHex((ftell f) as integer)) t.count hdr.offsets.count doDump)
	
	for i = 1 to hdr.offsets.count do (
		fseek f hdr.offsets[i] #seek_set
		size = readlong f #unsigned
		type = readlong f #unsigned
		unk1 = readshort f -- GTF.XTD  00, 01, or 02
		unk2 = readshort f -- the nth file in respective GTF
		unk3 = readshort f
		unk4 = readshort f
		
		if doDump == true then (
			if size > 0x10 then ( -- indexed textures take up exactly 0x10 bytes
				-- if debugMsg == true do (format "\tfound GTF at 0x%\n" (bit.intAsHex((ftell f) as integer)))
				if i <= t.count then ( --  more like if .GTF.XTD was not opened, we have names for embedded textures after we parsed  XMD
					texture_path = (getFilenamePath fpath) + t[i].texname + ".dds"
					t[i].tex_path = texture_path
						dumpGFT texture_path -- unique texture embedded in XTD
				) else (
					dumpGFT(fpath + "_tex_" + (paddstring 3 i) + ".dds") -- we hit this when .GTF.XTD gets opened
				)
			) else ( -- shared texture
				texture_path = (getFilenamePath fpath) + "AREA_ZZ_" + (paddstring 2 unk1) + ".GTF_tex_" + (paddstring 3 (unk2+1)) + ".dds"
				t[i].tex_path = texture_path
			)
		) else ( -- we're not dumping textures here but are here to prefill t array with texture paths since we depend on them in buildObj()
			if size > 0x10 then (
				texture_path = (getFilenamePath fpath) + t[i].texname + ".dds"
				t[i].tex_path = texture_path
			) else (
				texture_path = (getFilenamePath fpath) + "AREA_ZZ_" + (paddstring 2 unk1) + ".GTF_tex_" + (paddstring 3 (unk2+1)) + ".dds"
				t[i].tex_path = texture_path
			)
		)
		--if debugMsg == true and t.count > 0 do (format "\ttexture % path is:\n\t%\n" t[i].texname t[i].tex_path)
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
	
fn getType07 strArray strIndex = ( -- materials data
	global f, g, m
	local p = ftell f
	local material = _material()
	readBElong f
	readBElong f
	readBElong f
	count = readBElong f
	
	material.mat_str_index = strIndex
	material.submatcount = count

	-- if debugMsg == true do (format "material sub block, submatcount is %, read 1 long past count, now at 0x%\n" count (bit.intAsHex((ftell f) as integer)))
		
	for i = 1 to count do (
		p = ftell f
		type = readBElong f
		size = readBElong f
		unk1 = readBElong f -- in case of 0x08 it seems to be an index to global texture array, many times 0x06 also has this index
		unk2 = readBElong f -- in case of type 0x06 this usually is a start of string
		case type of (
			-- 0x00 -- the texture that is associated with this material often is of size 0x30 and not 0x20 and contains some floats
			0x00: ( -- copy paste of 0x08, i couldn't couple "0x00 or 0x08:" for some reason
				if debugMsg == true do (format "\tsubmaterial [%] tex index %?, unk2 is %\n" type unk1 unk2)
				map = _matbitmap()
				map.name = readNullStr f
				map.index = unk1
				append material.mat_bitmaps map
			)
			0x02: (
				[(readBEfloat f),(readBEfloat f),(readBEfloat f),(readBEfloat f)]
				[(readBEfloat f),(readBEfloat f),(readBEfloat f),(readBEfloat f)]
				[(readBEfloat f),(readBEfloat f),(readBEfloat f),(readBEfloat f)]
				[(readBEfloat f),(readBEfloat f),(readBEfloat f),(readBEfloat f)]
				[(readBEfloat f),(readBEfloat f),(readBEfloat f),(readBEfloat f)]
				[(readBEfloat f),(readBEfloat f),(readBEfloat f),(readBEfloat f)]
				[(readBEfloat f),(readBEfloat f),(readBEfloat f),(readBEfloat f)]
				if debugMsg == true do (format "\tdone NOTHING about submaterial [%], unk1: %, unk2: %\n" type unk1 unk2)
			)
			0x03: (
				readBElong f
				readBElong f
				readBElong f
				readBElong f
				
				--print strArray[idx]
				if debugMsg == true do (format "\tdone NOTHING about submaterial [%], unk1: %, unk2: %\n" type unk1 unk2)
			)
			0x04: ( -- vexXenon thing, seems like 4 longs following this string are zeros wherever i look
			)
			0x05: ( -- seems like 16 bytes in size, and unk1 and unk2 seems to store some count or index
			    -- unk2 counts sequentally, from 1 to 6 e.g when there are 3 bitmpas, or 1~4 when 2 bitmaps
				-- unk1 seems to follow weird pattern: 0x00 0x03 0x02 0x09 0x08 0x0B
				-- this sub type seems to come before 0x08 aka bitmaps
				if debugMsg == true do (format "\tsubmaterial [%], unk1: %, unk2: %\n" type unk1 unk2)
			)
			0x06: ( -- the sky texture in AREA_ZZ.CORE at 0x12d20h has this, and many more TXDs
				pos = ftell f
				fseek f -4 #seek_cur
				str = readNullStr f
				if findString str "depth_type" != undefined then (
					fseek f (pos+32) #seek_set
					depth_type = readBELong f
					material.depth_type = depth_type
					if debugMsg == true do (format "\tDEPTH TYPE: %\n" depth_type)
				) else (
					if debugMsg == true do (format "\tdone NOTHING about submaterial [%], unk1: %, str:  %\n" type unk1 str)
				)
			)
			-- 0x00 -- the texture that is associated with this material often is of size 0x30 and not 0x20 and contains some floats
			0x08: (
				if debugMsg == true do (format "\tsubmaterial [%] tex index %?, unk2 is %\n" type unk1 unk2)
				map = _matbitmap()
				map.name = readNullStr f
				map.index = unk1
				append material.mat_bitmaps map
			)
			0x09: (
				readBElong f
				readBElong f
				readBElong f
				readBElong f
				if debugMsg == true do (format "\tdone NOTHING about submaterial [%], unk1: %, unk2: %\n" type unk1 unk2)
			)
			0x0B: (
				if debugMsg == true do (format "\tdone NOTHING about submaterial [%], unk1: %, unk2: %\n" type unk1 unk2)
			)
			-- 0x0C some reflection matrix? i saw r33.car have this at 0x23f3c0 and the material name was body_refmat, another one was glass_refmat at 0x23f500
			default : (
				if debugMsg == true do (format "\tunknown submaterial type [%] at 0x%, size %, unk1 %, unk2 %\n" type (bit.intAsHex((ftell f) as integer)) size unk1 unk2)
			)
		)
		fseek f (p + size) #seek_set
	)
	
	append m material
)

fn getType08 objname matid strArray = ( -- geomety data
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
				triangle_strip f count matid
			)
			0x02: ( -- position
				for i = 1 to count do (
					append g.position (RH2LH([(readBEfloat f),(readBEfloat f),(readBEfloat f)]))
				)
			)
			0x03: ( -- colours
				if debugMsg == true do (format "\tdone NOTHING about colors vertex attribute\n")
			)
			0x04: ( -- normals
				if debugMsg == true do (format "\tdone NOTHING about normals vertex attribute\n")
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
				format "\terror UNSUPPORTED vertex format [%] at 0x%\n" comp (bit.intAsHex((getPos) as integer))
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
		
	buildObj objname strArray
)

fn getType12 strArray strIndex = ( -- texture data
	global f, t
	local texture = _texture()

	offset = readBElong f
	texture.offset_nth_in_xtd = offset
	texture.tex_str_index = strIndex
	texture.texname += strArray[strIndex] -- hack to get texname getTXD scope
	if debugMsg == true do (format "\ttexture is at %th offset in TXD\n" offset)
	
	append t texture
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

-- this function is called when 0x0 long magic is encountered in XMD file container
-- arg1's position usually will be at "Bp" section here
fn getStuff pos = (
	global f
	local p = ftell f, strArray = #(), boneArray = #(), subHeaderArray = #()
	fseek f 0x80 #seek_cur -- FIX ME, NOTICE THAT IT SEEK EXTRA 80h FROM CURR POS, well no one gives a fuck atm
	
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
			-- if debugMsg == true do block_name += (i as string) + " " -- creates block names such as "1 Detail" or  "3 mat_sitamichi00_sh" forgot what for?
			if sb.string_index > 0 and sb.string_index <= strArray.count do (
				block_name += strArray[(sb.string_index)]
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
									format "illegal parent, possibly same node or ancestor node [index:%(%) parent:%]\n" \
										boneArray.count sb.unk3 sb.unk2
								)
							)
						)
					)
				)
				0x05: ( -- bounding box
					if debugMsg == true do (format "Bounding Box @ 0x%\n" (bit.intAsHex((table.offsets[i]) as integer)))
					getType05(sb)
				)
				0x07: ( -- materials
					if debugMsg == true do (format "Material @ 0x%\n\tname: %, unk2 %, unk3 %\n" (bit.intAsHex((table.offsets[i]) as integer)) block_name (sb.unk2 as string) (sb.unk3 as string))
					getType07 strArray sb.string_index
				)
				0x08: ( -- geometry
					if debugMsg == true do (format "Geometry @ 0x%\n\tname: %, unk2 %, unk3 %\n" (bit.intAsHex((table.offsets[i]) as integer)) block_name (sb.unk2 as string) (sb.unk3 as string))
					if impMsh == true do (
						getType08 block_name sb.unk3 strArray
					)
				)
				0x0C: ( -- texture names
					if debugMsg == true do (format "Texture @ 0x%\n\tname: %, unk2 %, unk3 %, sub block size: %\n" (bit.intAsHex((table.offsets[i]) as integer)) block_name (sb.unk2 as string) (sb.unk3 as string) sb.size)
					getType12 strArray sb.string_index
				)
				0x11: ( -- IK Bone
					if debugMsg == true do (format "IK Bone @ 0x%\n\tname: %, unk2 %, unk3 %\n" (bit.intAsHex((table.offsets[i]) as integer)) block_name (sb.unk2 as string) (sb.unk3 as string))
				)
				0x15: ( -- string data
				)
				default: (
					format "sub block not supported [%] at 0x%\n" \
						sb.type (bit.intAsHex((table.offsets[i]) as integer))
				)
			)

		) -- end of sub block loop
	) else (
		format "failed to seek to table\n"
	)
	if debugMsg == true do (
		format "\nstring table\n"
		for i = 1 to strArray.count do (
			format "%:\t%\n" i strArray[i]
		)
		format "\n"
	)
)	

	
-- this fn reads first long of a file called magic and decides what to make of it
-- GTF stores multiple headerless DDS image, some even are 8888:32bit
fn readBinary filen = (
	global f, currentFilen = filen, offToXTDofCurrentXMD, m, t, didPrepopulateT
	pos = ftell f
	local magic = readlong f #unsigned
	fseek f -4 #seek_cur
	case magic of (
		0x01444D58: ( -- XMD (Xtreme Model Data)
			hdr = getHeader()
			
			-- when hitting XMD code expects to work on empty material and texture arrays so then:
			free m
			free t
			didPrepopulateT = false
			-- i'm assuming that every XMD is accompanied by XTD, we need this to have prepopulated path to textures by time we get to buildObj()
			offToXTDofCurrentXMD = hdr.offsets[2];
			if debugMsg == true do (format "\nparsing XMD at 0x%\n" (bit.intAsHex((pos) as integer)))
			
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
						format "error: new block type [%] at 0x%\n" \
							filetype (bit.intAsHex((hdr.offsets[d]) as integer))
					)
				)
			)

			if printTextureStats == true do (
				format "\nall parsed texture names, count: %\n" t.count
				for i = 1 to t.count do (
					format "%:\t%\n" i t[i].texname
				)
				
				format "\nHANDLED THESE TEXTURES, count: %\n" handledTheseTextures.count
				for i = 1 to handledTheseTextures.count do (
					format "%:\t%\n" i handledTheseTextures[i]
				)
				free handledTheseTextures
				
				format "\nOPACITY TEXTURES, count: %\n" opacityBitmapList.count
				for i = 1 to opacityBitmapList.count do (
					format "%:\t%\n" i opacityBitmapList[i]
				)
				free opacityBitmapList
				
				format "\nSPECULAR TEXTURES, count: %\n" specularBitmapList.count
				for i = 1 to specularBitmapList.count do (
					format "%:\t%\n" i specularBitmapList[i]
				)
				free specularBitmapList
				
				format "\nREFLECTION TEXTURES, count: %\n" reflectionBitmapList.count
				for i = 1 to reflectionBitmapList.count do (
					format "%:\t%\n" i reflectionBitmapList[i]
				)
				free reflectionBitmapList
				
				format "\nNORMAL TEXTURES, count: %\n" normalBitmapList.count
				for i = 1 to normalBitmapList.count do (
					format "%:\t%\n" i normalBitmapList[i]
				)
				free normalBitmapList
				
				format "\nMATERIALS WITH NO TEXTURES, count: %\n" noTextureMaterialList.count
				for i = 1 to noTextureMaterialList.count do (
					format "%:\t%\n" i noTextureMaterialList[i]
				)
				free noTextureMaterialList
				
				format "\nGEOMETRY WITH NO MATERIAL, count: %\n" noMaterialList.count
				for i = 1 to noMaterialList.count do (
					format "%:\t%\n" i noMaterialList[i]
				)
				free noMaterialList
			)
		)
		0x00445458: ( -- XTD (Xtreme Texture Data)
			getTXD (getTXD_header()) ((getFilenamePath filen)+(getFilenameFile filen)) true
		)
		0x00000501: ( -- GTF
			dumpGFT((getFilenamePath filen)+(getFilenameFile filen)+"_tex_001.dds")
		)
	)
)

fn openFilen filen = (
	global f, m, t, didPrepopulateT
	format "opening file %\n" filen
	if filen != undefined and doesFileExist filen == true then (
		try (fclose f) catch(gc())
		f = fopen filen "rb"
		if clearScene == true do (delete $*)

		readBinary(filen)
		free m -- it's super important to have these cleared for next file
		free t
		didPrepopulateT = false

		if debugMsg == true do (format "\nlast read at 0x%\n" (bit.intAsHex((ftell f) as integer)))
		format "finished parsing file %\n" filen
		fclose f
		return true
	) else (
		format "failed to open %\n" filen
		return false
	)
)



-- builds up stream of formatted strings
fn buildFilePaths sstream prefix start end  = (
	if start == 0 do ( format "%_000.GRID\n" prefix to:sstream; start = 1 )
	for i = start to end do (
		format "%_%%\n" prefix (formattedPrint i format:".3d" as string)  ".GRID" to:sstream
	)
	sstream
)

fn wanganMidnightLoadGinzaArea parentDir = (
	filenames = stringstream ""
	buildFilePaths filenames (parentDir + "AREA_C1_BUIL_CUT_C1_GIN") 0 6
	buildFilePaths filenames (parentDir + "AREA_C1_ROAD_MDL") 64 74

	seek filenames 0
	while eof filenames == false do (
		filen = readLine filenames
		openFilen(filen)
	)
)

fn wanganMidnightLoadC1 parentDir = (
	filenames = stringstream ""
	buildFilePaths filenames (parentDir + "AREA_C1_BUIL_CUT_C1_AKA") 0 5
	buildFilePaths filenames (parentDir + "AREA_C1_BUIL_CUT_C1_CHIDO") 0 7
	buildFilePaths filenames (parentDir + "AREA_C1_BUIL_CUT_C1_EDO") 0 4
	buildFilePaths filenames (parentDir + "AREA_C1_BUIL_CUT_C1_FREE") 0 26
	buildFilePaths filenames (parentDir + "AREA_C1_BUIL_CUT_C1_GIN") 0 6
	buildFilePaths filenames (parentDir + "AREA_C1_BUIL_CUT_C1_MIYA") 0 3
	buildFilePaths filenames (parentDir + "AREA_C1_BUIL_CUT_C1_SIBA") 0 4
	buildFilePaths filenames (parentDir + "AREA_C1_BUIL_CUT_C1_SIO") 0 4
	buildFilePaths filenames (parentDir + "AREA_C1_ROAD_MDL") 0 81

	seek filenames 0
	while eof filenames == false do (
		filen = readLine filenames
		openFilen(filen)
	)
)

fn wanganMidnightLoad911GO parentDir = (
	filenames = stringstream ""
	-- 9GO
	buildFilePaths filenames (parentDir + "AREA_9GO_BUIL_CUT_9GO_FREE") 0 11
	buildFilePaths filenames (parentDir + "AREA_9GO_BUIL_CUT_9GO_FUKA") 0 6
	buildFilePaths filenames (parentDir + "AREA_9GO_ROAD_MDL") 0 29
	-- 11GO
	buildFilePaths filenames (parentDir + "AREA_11GO_BUIL_CUT_11GO_DAI") 0 2
	buildFilePaths filenames (parentDir + "AREA_11GO_BUIL_CUT_11GO_FREE") 0 8
	buildFilePaths filenames (parentDir + "AREA_11GO_BUIL_CUT_11GO_WAN") 0 13
	buildFilePaths filenames (parentDir + "AREA_11GO_ROAD_MDL") 0 54

	seek filenames 0
	while eof filenames == false do (
		filen = readLine filenames
		openFilen(filen)
	)
)

fn wanganMidnightLoad9GO parentDir = (
	filenames = stringstream ""
	-- 9GO
	buildFilePaths filenames (parentDir + "AREA_9GO_BUIL_CUT_9GO_FREE") 0 11
	buildFilePaths filenames (parentDir + "AREA_9GO_BUIL_CUT_9GO_FUKA") 0 6
	buildFilePaths filenames (parentDir + "AREA_9GO_ROAD_MDL") 0 29

	seek filenames 0
	while eof filenames == false do (
		filen = readLine filenames
		openFilen(filen)
	)
)

fn wanganMidnightLoad11GO parentDir = (
	filenames = stringstream ""
	-- 11GO
	buildFilePaths filenames (parentDir + "AREA_11GO_BUIL_CUT_11GO_DAI") 0 2
	buildFilePaths filenames (parentDir + "AREA_11GO_BUIL_CUT_11GO_FREE") 0 8
	buildFilePaths filenames (parentDir + "AREA_11GO_BUIL_CUT_11GO_WAN") 0 13
	buildFilePaths filenames (parentDir + "AREA_11GO_ROAD_MDL") 0 54

	seek filenames 0
	while eof filenames == false do (
		filen = readLine filenames
		openFilen(filen)
	)
)

fn wanganMidnightLoadWangan parentDir = (
	filenames = stringstream ""

	buildFilePaths filenames (parentDir + "AREA_WN_I1_BUIL_CUT_I1_FREE") 0 3
	buildFilePaths filenames (parentDir + "AREA_WN_I1_ROAD_MDL") 0 17
	buildFilePaths filenames (parentDir + "AREA_WN_I2_BUIL_CUT_I2") 0 7
	buildFilePaths filenames (parentDir + "AREA_WN_I2_BUIL_CUT_I2_FREE") 0 3
	buildFilePaths filenames (parentDir + "AREA_WN_I2_ROAD_MDL") 0 13
	buildFilePaths filenames (parentDir + "AREA_WN_I3_BUIL_CUT_I3_FREE") 0 2
	buildFilePaths filenames (parentDir + "AREA_WN_I3_ROAD_MDL") 0 12
	buildFilePaths filenames (parentDir + "AREA_WN_J1_BUIL_CUT_J1_FREE") 0 3
	buildFilePaths filenames (parentDir + "AREA_WN_J1_ROAD_MDL") 0 8
	buildFilePaths filenames (parentDir + "AREA_WN_J2_BUIL_CUT_J2_FREE") 0 2
	buildFilePaths filenames (parentDir + "AREA_WN_J2_ROAD_MDL") 0 24
	buildFilePaths filenames (parentDir + "AREA_WN_K1_BUIL_CUT_K1_A") 0 14
	buildFilePaths filenames (parentDir + "AREA_WN_K1_BUIL_CUT_K1_B") 0 10
	buildFilePaths filenames (parentDir + "AREA_WN_K1_BUIL_CUT_K1_FREE") 0 19
	buildFilePaths filenames (parentDir + "AREA_WN_K1_ROAD_MDL") 0 39
	buildFilePaths filenames (parentDir + "AREA_WN_K2_BUIL_CUT_K2_FREE") 0 15
	buildFilePaths filenames (parentDir + "AREA_WN_K2_ROAD_MDL") 0 17

	seek filenames 0
	while eof filenames == false do (
		filen = readLine filenames
		openFilen(filen)
	)
	
	openFilen "C:\\NIGHT\\AREA_WN_J1_BUIL_J1_RYOK.GRID"
)

fn wanganMidnightLoadYokohane parentDir = (
	filenames = stringstream ""

	buildFilePaths filenames (parentDir + "AREA_YH_L0_BUIL_CUT_L0_DAIK_A") 0 8
	buildFilePaths filenames (parentDir + "AREA_YH_L0_BUIL_CUT_L0_DAIK_B") 0 7
	buildFilePaths filenames (parentDir + "AREA_YH_L0_BUIL_CUT_L0_FREE") 0 17
	buildFilePaths filenames (parentDir + "AREA_YH_L0_BUIL_CUT_L0_YH") 0 13
	buildFilePaths filenames (parentDir + "AREA_YH_L0_ROAD_MDL") 0 10
	buildFilePaths filenames (parentDir + "AREA_YH_L1_BUIL_CUT_L1") 0 31
	buildFilePaths filenames (parentDir + "AREA_YH_L1_BUIL_CUT_L1_FREE") 0 8
	buildFilePaths filenames (parentDir + "AREA_YH_L1_ROAD_MDL") 0 9
	buildFilePaths filenames (parentDir + "AREA_YH_L2_BUIL_CUT_L2") 0 21
	buildFilePaths filenames (parentDir + "AREA_YH_L2_BUIL_CUT_L2_FREE") 0 3
	buildFilePaths filenames (parentDir + "AREA_YH_L2_ROAD_MDL") 0 10
	buildFilePaths filenames (parentDir + "AREA_YH_L3_BUIL_CUT_L3") 0 15
	buildFilePaths filenames (parentDir + "AREA_YH_L3_BUIL_CUT_L3_FREE") 0 9
	buildFilePaths filenames (parentDir + "AREA_YH_L3_ROAD_MDL") 0 10
	buildFilePaths filenames (parentDir + "AREA_YH_M1_BUIL_CUT_M1") 0 9
	buildFilePaths filenames (parentDir + "AREA_YH_M1_BUIL_CUT_M1_FREE") 0 6
	buildFilePaths filenames (parentDir + "AREA_YH_M1_ROAD_MDL") 0 15
	buildFilePaths filenames (parentDir + "AREA_YH_M2_BUIL_CUT_M2") 0 18
	buildFilePaths filenames (parentDir + "AREA_YH_M2_BUIL_CUT_M2_FREE") 0 7
	buildFilePaths filenames (parentDir + "AREA_YH_M2_ROAD_MDL") 0 18

	seek filenames 0
	while eof filenames == false do (
		filen = readLine filenames
		openFilen(filen)
	)
)

-- code execution starts here, first we clear listener window
clearlistener()

-- globals below are freely accessible
if assettoCorsaWriteConfig == true do (
	configFname = assettoCorsaConfigPath + assettoCorsaConfigFname + ".ini"
	try (fclose acConfig) catch(gc())
	acConfig = fopen configFname "w"
	--format "failed to open %.ini for writing\n" assettoCorsaConfigFname
)

if guiEnabled == false then (
	--local filen = ""; openFilen(filen)
	openFilen "C:\\NIGHT\\AREA_ZZ.CORE"
	openFilen "C:\\NIGHT\\AREA_ZZ.WATER"
	
	wanganMidnightLoadC1 "C:\\NIGHT\\"
	--wanganMidnightLoad911GO "C:\\NIGHT\\"
	--wanganMidnightLoadWangan "C:\\NIGHT\\"
	--wanganMidnightLoadYokohane "C:\\NIGHT\\"
	
	if assettoCorsaWriteConfig == true do ( assettoCorsaConfigClose() )
	--
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
			)
		)
		on PS3_WANGANM_IMPORTER close do (
			if assettoCorsaWriteConfig == true do ( assettoCorsaConfigClose() )
		)
	)
	createdialog PS3_WANGANM_IMPORTER
)
