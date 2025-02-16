local ChunkMeshGenerator = {}

ChunkMeshGenerator.CHUNK_SIZE = 16
ChunkMeshGenerator.CHUNK_SIZE_P = ChunkMeshGenerator.CHUNK_SIZE + 2
ChunkMeshGenerator.CHUNK_SIZE_P2 = ChunkMeshGenerator.CHUNK_SIZE_P * ChunkMeshGenerator.CHUNK_SIZE_P
ChunkMeshGenerator.CHUNK_SIZE_P3 = ChunkMeshGenerator.CHUNK_SIZE_P2 * ChunkMeshGenerator.CHUNK_SIZE_P
ChunkMeshGenerator.SCALE = 60
ChunkMeshGenerator.BLOCK_TYPES = 3
ChunkMeshGenerator.BLOCK_SIZE = 4


-- Method for setting bits in a specific buffer with a certain state 1/0
function ChunkMeshGenerator.setBit(buf, bitPosition, state, offset, readf, writef)
	-- Read the current byte value at offset 0
	local byte = readf(buf, offset)
	if state then
		-- Set the bit using bitwise OR
		byte = bit32.bor(byte, bit32.lshift(1, bitPosition))
	else
		-- Clear the bit using bitwise AND with the complement
		byte = bit32.band(byte, bit32.bnot(bit32.lshift(1, bitPosition)))
	end
	-- Write the modified byte back to the buffer
	writef(buf, offset, byte)
end

-- Function to get a bit state from a buffer at a specific bit position.
function ChunkMeshGenerator.getBit(buf, bitPosition, row, f)
	-- Read the current byte value at offset 0
	local byte = f(buf, row)
	-- Check if the specific bit is set
	return bit32.band(byte, bit32.lshift(1, bitPosition)) ~= 0
end

-- Util function to print the buffer as a binary grid. See all bits in a buffer.
function ChunkMeshGenerator.printBufferAsBinaryGrid(buf, offset, readf, size, extend, step)
	for i = 0, extend or 30, step or 2 do
		--print("Offset:", i)
		local b = readf(buf, i)
		--print("16-bit value:", b)
		local binaryString = ""
		for bitPos = 0,size do
			local v = ChunkMeshGenerator.getBit(buf, bitPos, offset or i, readf)
			if v then
				binaryString = binaryString .. "1"
			else
				binaryString = binaryString .. "0"
			end
		end
		print(binaryString)
	end
end

-- Function called outside of the module to create the chunk mesh vertices in the chunkMesh.
function ChunkMeshGenerator.createChunkMesh(chunkX : number, chunkY : number, chunkZ : number)
	local data = ChunkMeshGenerator.generatePlaneTable()
	local axisCols = ChunkMeshGenerator.buildChunk(chunkX, chunkY, chunkZ)
	local colFaceMasks = ChunkMeshGenerator.cullFaces(axisCols)

	data = ChunkMeshGenerator.generateAxisPlanes(chunkX, chunkY, chunkZ, colFaceMasks, data)
	local quadData = ChunkMeshGenerator.greedyMeshChunk(data)
	
	return quadData
end

-- Generates the data table required to store all of the planes for greedy meshing.
function ChunkMeshGenerator.generatePlaneTable()
	local data = {}
	for axis = 1, 6 do
		data[axis] = {} -- Each axis will hold buffers for `y` slices
		for blockType = 1, ChunkMeshGenerator.BLOCK_TYPES do
			data[axis][blockType] = {}
		end
	end
	return data
end

-- Constructs the chunk using a noise function to assign bits in each axis direction.
function ChunkMeshGenerator.buildChunk(chunkX, chunkY, chunkZ)
	local axisCols : buffer = buffer.create(ChunkMeshGenerator.CHUNK_SIZE_P2 * 4 * 3) -- 3 lots of 34x34 grids stored at 32 bits

	for y = 0, ChunkMeshGenerator.CHUNK_SIZE_P-1 do
		for z = 0, ChunkMeshGenerator.CHUNK_SIZE_P-1 do
			for x = 0, ChunkMeshGenerator.CHUNK_SIZE_P-1 do
				
				local squash = (chunkY * ChunkMeshGenerator.CHUNK_SIZE + y) * 0.09

				if (math.noise((chunkX * ChunkMeshGenerator.CHUNK_SIZE + x)/ChunkMeshGenerator.SCALE, (chunkY * ChunkMeshGenerator.CHUNK_SIZE + y)/ChunkMeshGenerator.SCALE, (chunkZ * ChunkMeshGenerator.CHUNK_SIZE + z)/ChunkMeshGenerator.SCALE) * 2.2) + squash < 0 then	
					-- XZ AXIS
					local index = (x + (z * ChunkMeshGenerator.CHUNK_SIZE_P)) * 4
					ChunkMeshGenerator.setBit(axisCols, y, true, index, buffer.readu32, buffer.writeu32)

					-- ZY AXIS
					index = (z + (y * ChunkMeshGenerator.CHUNK_SIZE_P) + ChunkMeshGenerator.CHUNK_SIZE_P2) * 4
					ChunkMeshGenerator.setBit(axisCols, x, true, index, buffer.readu32, buffer.writeu32)

					-- XY AXIS
					index = (x + (y * ChunkMeshGenerator.CHUNK_SIZE_P) + ChunkMeshGenerator.CHUNK_SIZE_P2 * 2) * 4
					ChunkMeshGenerator.setBit(axisCols, z, true, index, buffer.readu32, buffer.writeu32)
				end
			end
		end
	end
	return axisCols
end

-- Function to cull faces that are unseen by the player from the surface.
function ChunkMeshGenerator.cullFaces(axisCols : buffer)
	local colFaceMasks : buffer = buffer.create(ChunkMeshGenerator.CHUNK_SIZE_P2 * 4 * 3 * 2) -- Same as Axis Cols, but theres 2x faces for each row
	
	for axis = 0, 2 do
		for i = 0, ChunkMeshGenerator.CHUNK_SIZE_P2 - 1 do
			local index1 = ((ChunkMeshGenerator.CHUNK_SIZE_P2 * (axis * 2 + 1)) + i) * 4
			local index2 = ((ChunkMeshGenerator.CHUNK_SIZE_P2 * (axis * 2 + 0)) + i) * 4
			local colIndex = ((ChunkMeshGenerator.CHUNK_SIZE_P2 * axis) + i) * 4
			local col = buffer.readu32(axisCols, colIndex)
			
			buffer.writeu32(colFaceMasks, index1, bit32.band(col, bit32.bnot(bit32.rshift(col, 1)))) -- Correspond to the UP/RIGHT/BACK faces
			buffer.writeu32(colFaceMasks, index2, bit32.band(col, bit32.bnot(bit32.lshift(col, 1)))) -- Correspond to the DOWN/LEFT/FORWARD
		end
	end
	
	return colFaceMasks
end

-- Function to create all planes for all axes to be greedy meshed.
function ChunkMeshGenerator.generateAxisPlanes(chunkX, chunkY, chunkZ, colFaceMasks, data)
	for axis = 0, 5 do
		for z = 0, ChunkMeshGenerator.CHUNK_SIZE-1 do
			for x = 0, ChunkMeshGenerator.CHUNK_SIZE-1 do
				
				local col_index = ((1 + x) + ((z+1) * ChunkMeshGenerator.CHUNK_SIZE_P) + ChunkMeshGenerator.CHUNK_SIZE_P2 * axis) * 4
				local col = bit32.rshift(buffer.readu32(colFaceMasks, col_index), 1)
				col = bit32.band(col, bit32.bnot(bit32.lshift(1, ChunkMeshGenerator.CHUNK_SIZE)))
				
				-- FIND FACES
				while col ~= 0 do
					local y
					y = bit32.countrz(col)
					col = bit32.band(col, col-1)

					local voxelPos
					if axis == 0 or axis == 1 then
						voxelPos = Vector3.new(x, y, z)
					elseif axis == 2 or axis == 3 then
						voxelPos = Vector3.new(y, z, x)
					else
						voxelPos = Vector3.new(x, z, y)
					end
					
					local blockType = 1 -- Stone
					local offset = (voxelPos + Vector3.new(chunkX, chunkY, chunkZ) * ChunkMeshGenerator.CHUNK_SIZE)/5
					if chunkY * ChunkMeshGenerator.CHUNK_SIZE + voxelPos.Y > 5 - math.noise(offset.X, offset.Y, offset.Z) * 6.5 then
						blockType = 2 -- Grass
					elseif chunkY * ChunkMeshGenerator.CHUNK_SIZE + voxelPos.Y > 0 - math.noise(offset.X + 1000, offset.Y + 1000, offset.Z + 1000) * 4.5 then
						blockType = 3 -- Snow
					end
					
					local dataPlane = data[axis+1][blockType][y+1]
					if not dataPlane then 
						data[axis+1][blockType][y+1] = buffer.create(ChunkMeshGenerator.CHUNK_SIZE * ChunkMeshGenerator.CHUNK_SIZE * 2)
					end
					ChunkMeshGenerator.setBit(data[axis+1][blockType][y+1], z, true, x * 2, buffer.readu16, buffer.writeu16)
					
				end
			end
		end
	end
	return data
end

-- Function that greedy meshes all axes and adds the resulting quads to the vertex group.
function ChunkMeshGenerator.greedyMeshChunk(data)
	for axis = 1, 6 do
		for blockType = 1, ChunkMeshGenerator.BLOCK_TYPES do
			for y = 0, ChunkMeshGenerator.CHUNK_SIZE - 1 do
				-- Get the buffer for this axis and `y`
				local planeBuffer = data[axis][blockType][y+1]

				if not planeBuffer then continue end

				-- Pass the buffer to the greedy meshing function
				local quads = ChunkMeshGenerator.binaryMesherPlane(planeBuffer)
				data[axis][blockType][y+1] = quads
				
			end
		end
	end
	return data
end


-- Function that completes the binary greedy meshing returnign the quads for that plane.
function ChunkMeshGenerator.binaryMesherPlane(chunk : buffer)
	local greedyQuads = {}
	for row = 0, ChunkMeshGenerator.CHUNK_SIZE - 1 do
		local y = 0
		while y < ChunkMeshGenerator.CHUNK_SIZE do

			local rowBits = buffer.readu16(chunk, row * 2)
			local airHeight = bit32.countrz(bit32.rshift(rowBits, y))
			y += airHeight
			
			if y >= ChunkMeshGenerator.CHUNK_SIZE then break end

			local flippedRow = bit32.band(bit32.rshift(bit32.bnot(rowBits), y), 0xFFFF)
			local h = bit32.countrz(flippedRow)
			local h_as_mask = bit32.lshift(1, h) - 1
			local mask = bit32.lshift(h_as_mask, y)
			local w = 2

			while row + w < ChunkMeshGenerator.CHUNK_SIZE * 2 do
				local nextRowNum = buffer.readu16(chunk, row * 2 + w)
				local nextRowNumShift = bit32.rshift(nextRowNum, y)

				local nextRow = bit32.band(nextRowNumShift, h_as_mask)

				if h_as_mask ~= nextRow then break end

				local newNextRowData = bit32.band(nextRowNum, bit32.bnot(mask))
				buffer.writeu16(chunk, row * 2 + w, newNextRowData)
				w += 2
			end
			
			table.insert(greedyQuads, {y, w/2, h, row})
			y += h
		end
	end
	return greedyQuads
end

return ChunkMeshGenerator