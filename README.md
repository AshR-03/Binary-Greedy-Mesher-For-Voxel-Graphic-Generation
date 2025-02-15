# Binary-Greedy-Mesher-For-Voxel-Graphic-Generation-In-Lua

In this project, I showcase a fast method of greedy meshing adjacent quad faces for Lua using bitwise operations, Binary [buffers](https://create.roblox.com/docs/reference/engine/libraries/buffer) and [Editable Mesh](https://create.roblox.com/docs/reference/engine/classes/EditableMesh) Objects to render an optimised voxel world.

### This Project solves the following problems:
  - **`Slow greedy meshing times`** - The project uses **`bitwise operations`** encoded at **machine level** to greatly reduce the number of **clock cycles** used to greedy mesh a chunk of **voxels**.
  - **`Lack of face culling`** - The project greatly reduces the number of vertices and draw calls being made due to the use of **`Editable Meshes`** rather than traditional [Part](https://create.roblox.com/docs/reference/engine/classes/Part) based Methods.
  - **`Large Server Memory Consumption`** - The project utilises **buffers** to reduce overhead and store voxels as **`1 bit per block`**.

## Project Details

The importance of the project can be outlined by looking into the [Microprofiler](https://create.roblox.com/docs/studio/microprofiler) in Roblox Studio. The `Microprofiler` is used as an optimisation tool to identify **performance issues** and measure time taken to perform operations inside of scripts in each **frame**. Figure 1 shows a snippet from the microprofiler of the time taken for a `traditional greedy mesher` algorithm in Roblox Studio using parts to complete.


<img src="https://github.com/user-attachments/assets/fc2933ee-fcd5-4b80-bd22-0a8bcb6f4224" alt="Microprofiler Image" width="300"/>

*Figure 1 - A single greedy meshed chunk at 16x16 blocks taking 2.606ms to complete*

We can significantly reduce the amount of computation time used when greedy meshing by using a `binary greedy mesher` [^1][^2] . This algorithm is designed based on a set of bitwise operations on rows of `16 bit` binary numbers. Below are the steps of the algorithm implemented in this project for 16x16 chunks:

  - Build a buffer sized `18 * 18 * 4 * 3`, which contains an `18x18` 32 bit grid for each of the `3` X, Y and Z axes. We place a 1 in the bit positions where on that local axis, there is a solid block. We use 18 bits per chunk as we are also accounting for neighbouring    edge blocks.
  - Build a second buffer sized `18 * 18 * 4 * 3 * 2` which uses `bit32.band()`, `bit32.bnot()` and `bit32.rshift` bitwise operators to located the face edges for each axis. this `face location` buffer is `2x` the size of the buffer with the binary voxel data due to the     fact that each row of 32 bits will have a 2 faces on the same axis (6 faces for 3 axes).
  - Once we have the `face location` buffer, we generate a set of `binary face planes` for each of the 6 directions on the 3 axes. We **remove the 2 edge cases** as we do not want to account for the `neighbouring chunk faces` in the greedy mesher. A visualisation of     
  `1/16 axis planes` can be seen in figure 2:

  <img src="https://github.com/user-attachments/assets/c70054c2-55f9-4ba2-9ddd-41a904354fbb" alt="Axis Planes Image" width="300"/>

  *Figure 2 - A diagram of one of the 16 `axis planes` that will be passed in to the greedy meshing algorithm. The white Zeros represent the `16 bit face mask`, which will only contain a 1 if a face was detected when culling the faces*.

  - We store the axis planes using a `hash table`, which considers the `Y Bit position` seen in figure 2 to get the correct plane, the axis or `face direction`, and the block type (as only `identical block types` can be meshed together). The code to generate the **hash table** can be seen below:

    ```lua
    local data = {}
  	for axis = 1, 6 do
  		data[axis] = {} -- Each axis will hold buffers for `y` slices
  		for blockType = 1, ChunkMeshGenerator.BLOCK_TYPES do
  			data[axis][blockType] = {}
  		end
  	end
  	return data
    ```

  - Finally, we loop through each axis plane and `greedy mesh` each plane using bitwise operations to check and merge connected faces. This returns a `table of greedy meshed quad positions, widths and heights`. Using this table of meshes, we can render the quads using the `Editable image` function `AddVertex()`.

### Results

Returning to the `Microprofiler`, we can see a dramatic `decrease in render time` using the **binary greedy mesher** method in comparison to **traditional part methods**. Figure 3 shows the upper bound result for a single `16x16` chunk greedy mesh.

<p align="center">
  <img src="https://github.com/user-attachments/assets/4c8dbb0f-4e16-4f40-8dd4-d070d042315f" alt="Axis Planes Image 1" width="300"/>
  <img src="https://github.com/user-attachments/assets/e8f76210-9e1a-497c-8e83-c30eb6d09fe5" alt="Axis Planes Image 2" width="300"/>
</p>

*Figure 3 - Both **chunk initialisation** and **binary greedy meshing** computation times (total equivalent to the process in figure 1). Total computation time of `0.116ms` which gives a staggering `2.49ms` improvement over figure 1s chunk generation*

<img src="https://github.com/user-attachments/assets/6be719f1-2f25-4d1d-aac2-52c5f9b5f9ec" alt="Axis Planes Image 1" width="600"/>

*Figure 4 - Final result of rendering the `Editable mesh` chunks. Blocks of the **same blocktype** are meshed **separately** from one another, whilst also minimizing the amount of **quads rendered**.*

## Installation and Use

To use the `binary greedy mesher` in your local projects, download the `projectFile.rbxl` and open the application in `Roblox Studio`.


[^1]: Davis Morley, “Greedy Meshing Voxels Fast - Optimism in Design Handmade Seattle 2022,” YouTube, Feb. 01, 2023. https://www.youtube.com/watch?v=4xs66m1Of4A.
[^2]: Tantan, “Blazingly Fast Greedy Mesher - Voxel Engine Optimizations,” YouTube, Apr. 19, 2024. https://www.youtube.com/watch?v=qnGoGq7DWMc.
