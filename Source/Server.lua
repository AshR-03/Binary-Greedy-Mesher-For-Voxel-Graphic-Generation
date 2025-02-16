-- Run the binary greedy mesher on the chunk -1, 0, -1 in the 3D world.
local BinaryGreedyMesher = require(script.BinaryGreedyMesher)
local quadData = BinaryGreedyMesher.createChunkMesh(-1,0,-1)