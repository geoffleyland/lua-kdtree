--- n-dimensional kdtree spatial indexing.
--  A [kdtree](http://en.wikipedia.org/wiki/K-d_tree) is a data structure
--  for quickly finding out what objects in space intersect with a given query
--  volume.
--
--  This implements a read-only n-dimensional kdtree that can contain boxes
--  as well as points.
--
--  Read-only means that you build the kdtree once on a large set of data,
--  and query many times on that data set.  Once the kdtree is built, you
--  can't add objects to it.  This could be extended, but it's all I need
--  for the moment.
--
--  N-dimensional means that the kdtree works on 2D-spaces (like road maps),
--  a 3D spaces, and higher dimensional spaces.  At higher dimensions,
--  spatial querying makes less and less sense though.
--
--  The objects in the kdtree can be boxes as well as points.  I don't know
--  why, but many of the implementations I've can only contain points.
--
--  The kdtree can be written to a file.  This can be a text file, or, if
--  you're using [LuaJIT](http://luajit.org),
--  and have [ljsycall](https://github.com/justincormack/ljsyscall)
--  and luafilesystem,
--  a binary file.


local ok, ffi = pcall(require, "ffi")
if not ok then ffi = nil end
local lfs, mmapfile
local malloc, gcmalloc, free
if ffi then
  local cdefs = require"kdtree.cdefs"
  local ok
  ok, lfs = pcall(require, "lfs")
  if not ok then lfs = nil end
  ok, mmapfile = pcall(require, "mmapfile")
  if not ok then mmapfile = nil end

  if mmapfile and mmapfile.malloc then
    malloc, gcmalloc, free = mmapfile.malloc, mmapfile.gcmalloc, mmapfile.free
  else
    malloc, gcmalloc, free = cdefs.malloc, cdefs.gcmalloc, cdefs.free
  end
end


local math_ceil, math_huge, math_log = math.ceil, math.huge, math.log


------------------------------------------------------------------------------

local kdtree =
{
  -- I haven't tested this version much, so this is a bit of a guess
  DEFAULT_LEAF_SIZE = 100,
}
kdtree.__index = kdtree

local allocate, release_events

if ffi then
  allocate = function(tree, item_count)
    local dims = tree.dims
    local leaf_size = tree.leaf_size

    local event_estimate = dims * 2 * item_count
    tree.event_ptr = malloc(event_estimate, "struct kdtree_event")
    tree.event_count = 0

    tree.items = gcmalloc(item_count, "int32_t")
    tree.item_count = 0

    -- Hopefully leaf_estimate and node_estimate are large enough, because
    -- I haven't implemented any way for them to grow.  I do, now, have
    -- a check on their size (in new_leaf and new_node below).
    local leaf_estimate = math_ceil(item_count / leaf_size) * 4
    tree.leaves = gcmalloc(leaf_estimate, "struct kdtree_leaf")
    tree.leaf_count = 0
    tree.leaf_limit = leaf_estimate

    local node_estimate = math_ceil(item_count / leaf_size) * 4
    tree.nodes = gcmalloc(node_estimate, "struct kdtree_node")
    tree.node_count = 0
    tree.node_limit = node_estimate
  end

  release_events = function(tree)
    free(tree.event_ptr)
    tree.event_ptr, tree.event_count = nil, nil
  end

else
  allocate = function() end
  release_events = function() end
end


local function query_index_bounds(tree, index)
  return tree.raw_bounds(index, tree.min_space, tree.max_space)
end


local function query_object_bounds(tree, index)
  return tree.raw_bounds(tree.objects[index], tree.min_space, tree.max_space)
end


local function init(bounds, dims, leaf_size)
  local tree =
  {
    dims = dims,
    min_space = {},
    max_space = {},
    leaf_size = leaf_size or kdtree.DEFAULT_LEAF_SIZE,
    raw_bounds = bounds,
  }

  return setmetatable(tree, kdtree)
end


------------------------------------------------------------------------------

local new_event

if ffi then
  new_event = function(tree, x, type, item)
    local event = tree.event_ptr + tree.event_count
    tree.event_count = tree.event_count + 1
    event.x = x
    event.type = type
    event.item = item
    return event
  end
else
  new_event = function(tree, x, type, item)
    return { x=x, type=type, item=item }
  end
end


local function add_item(tree, item, axis_index, axis, count)
  local min, max = tree:bounds(item)
  min, max = min[axis_index], max and max[axis_index] or nil
  if max and max ~= min then
    axis[count+1] = new_event(tree, min, 1, item)
    count = count + 2
    axis[count] = new_event(tree, max, -1, item)
  else
    count = count + 1
    axis[count] = new_event(tree, min, 0, item)
  end
  return count
end


local function add_items(tree, lower, upper)
  local axes = {}
  for a = 1, tree.dims do
    local j = 0
    local axis = {}
    for i = lower, upper do
      j = add_item(tree, i, a, axis, j)
    end
    table.sort(axis, function(a, b) return a.x < b.x end)
    axes[a] = axis
  end

  return axes
end


------------------------------------------------------------------------------

local new_leaf, add_to_leaf

if ffi then
  new_leaf = function(tree, size)
    local lc = tree.leaf_count
    local leaf = tree.leaves + lc
    tree.leaf_count = lc + 1
    assert(tree.leaf_count <= tree.leaf_limit, "Too many leaves!")

    local ic = tree.item_count
    tree.item_count = ic + size
    leaf.first_item = ic
    leaf.last_item = ic + size - 1

    return leaf, -lc-1
  end

  add_to_leaf = function(tree, leaf, index, item)
    tree.items[leaf.first_item + index - 1] = item
  end

else
  new_leaf = function() return {} end

  add_to_leaf = function(tree, leaf, index, item)
    leaf[index] = item
  end
end


function build_leaf(tree, axis, item_count)
  local leaf, ret = new_leaf(tree, item_count)

  local i = 1
  for _, a in ipairs(axis) do
    if a.type >= 0 then
      add_to_leaf(tree, leaf, i, a.item)
      i = i + 1
    end
  end

  return ret or leaf
end


------------------------------------------------------------------------------

local new_node

if ffi then

  new_node = function(tree, axis, split, low, high, mid)
    local nc = tree.node_count
    local node = tree.nodes + nc
    tree.node_count = nc + 1
    assert(tree.node_count <= tree.node_limit, "Too many nodes!")
    return node, nc
  end

else
  new_node = function() return {} end
end


local function build_node(tree, axis, split, low, high, mid)
  local node, ret = new_node(tree)

  node.axis, node.split = axis, split
  node.low, node.high, node.mid = low, high, mid

  return ret or node
end


------------------------------------------------------------------------------

-- I just made this cost estimate up, I should really read some papers
local function split_cost(lcount, mcount, hcount)
  lcount = lcount + mcount
  hcount = hcount + mcount
  local itotal = 1 / (lcount + hcount)
  local lcost = lcount == 0 and 0 or lcount * itotal * math_log(lcount)
  local hcost = hcount == 0 and 0 or hcount * itotal * math_log(hcount)
  return lcost + hcost
end


local function new_axis_set(n)
  a = {}
  for i = 1, n do
    a[i] = {}
  end
  return a
end


local function split(tree, axes, item_count)
  if item_count < tree.leaf_size then
    return build_leaf(tree, axes[1], item_count)
  end

  -- Work out where we'd split along each axis and find the best
  local best_cost = math_huge
  local best_axis, best_x
  local best_lcount, best_mcount, best_hcount

  for ai, axis in ipairs(axes) do
    local lcount, mcount, hcount = 0, 0, item_count
    local i = 1
    while axis[i] do
      local x0 = axis[i].x
      while axis[i] and axis[i].x == x0 do
        local a = axis[i]
        if a.type >= 0 then mcount = mcount + 1; hcount = hcount - 1 end
        if a.type <= 0 then mcount = mcount - 1; lcount = lcount + 1 end
        i = i + 1
      end
      local c = split_cost(lcount, mcount, hcount)
      if c < best_cost then
        best_cost, best_axis, best_x, best_lcount, best_mcount, best_hcount =
          c, ai, x0, lcount, mcount, hcount
      end
    end
  end
--  print("COUNTS", best_lcount, best_mcount, best_hcount)

  if best_lcount == item_count or best_hcount == item_count then
    return build_leaf(tree, axes[1], item_count)
  end

  local temp_axes = axes.child_axes or new_axis_set(#axes)
  temp_axes.child_axes = temp_axes.child_axes or new_axis_set(#axes)

  for ai, axis in ipairs(axes) do
    local count = 1
    for _, a in ipairs(axis) do
      local min, max = tree:bounds(a.item)
      max = max or min
      if max[best_axis] <= best_x then
        temp_axes[ai][count] = a
        count = count + 1
      end
    end
    temp_axes[ai][count] = nil
  end
  local low_split = split(tree, temp_axes, best_lcount)

  for ai, axis in ipairs(axes) do
    local count = 1
    for _, a in ipairs(axis) do
      local min = tree:bounds(a.item)
      if min[best_axis] > best_x then
        temp_axes[ai][count] = a
        count = count + 1
      end
    end
    temp_axes[ai][count] = nil
  end
  local high_split = split(tree, temp_axes, best_hcount)

  for ai, axis in ipairs(axes) do
    local count = 1
    for _, a in ipairs(axis) do
      local min, max = tree:bounds(a.item)
      if max and
        min[best_axis] <= best_x and
        max[best_axis] > best_x then
        temp_axes[ai][count] = a
        count = count + 1
      end
    end
    temp_axes[ai][count] = nil
  end
  local mid_split = split(tree, temp_axes, best_mcount)

  return build_node(tree, best_axis, best_x, low_split, high_split, mid_split)
end


------------------------------------------------------------------------------

--- Build a kdtree.
--  The kdtree internally contains a list of indexes, either for you to use
--  directly, or as indexes into a table of objects.
--  Arguments to build are a bit of a mess.
--  `bounds` is a function that returns the bounds of an item as two tables:
--  `return { 1, 1 }, { 2, 2 })`.
--  Two tables with space for min and max are passed in as second and third
--  arguments to `bounds` as an optimisation to avoid creating too many small
--  tables, so `bounds` could be:
--
--      function bounds(i, min, max)
--        min[1], min[2] = i.left, i.bottom
--        max[1], max[2] = i.right, i.top
--        return min, max
--      end
--
--  If the object is a point then `bounds` can just return the first table.
--  @return the tree
function kdtree.build(
  bounds,       -- function: return the bounds of an item given the index of
                -- an item, or the item itself.
  dims,         -- integer: the number of dimensions for the kdtree. default
                -- is two.
  x,            -- ?integer|table: if `x` is an integer, then the kdtree
                -- is an index of the integers from x to y.  If x is a table
                -- then the kdtree is an index of the items in the array part
                -- of the table.
  y,            -- ?integer: if x is an integer, then y is the upper limit of
                -- the index in the kdtree.  If x is a table, then y is the
                -- leaf size of the table (optional, set to a default)
  z)            -- ?integer: if x is an integer, then z is the leaf size
                -- of the kdtree.
  local objects, lower, upper, leaf_size, item_count, wrapped_bounds
  if type(x) == "number" then
    lower, upper, leaf_size = x, y, z
    item_count = upper - lower + 1
    wrapped_bounds = query_index_bounds
  else
    objects, leaf_size = x, y
    lower, upper = 1, #objects
    item_count = upper
    wrapped_bounds = query_object_bounds
  end

  local tree = init(bounds, dims, leaf_size)
  tree.objects = objects
  allocate(tree, item_count)
  tree.bounds = wrapped_bounds
  local axes = add_items(tree, lower, upper)
  tree.root = split(tree, axes, item_count)
  release_events(tree)
  return tree
end


------------------------------------------------------------------------------

local function intersect_item(tree, min1, max1, min2, max2)
  max2 = max2 or min2
  for i = 1, tree.dims do
    if min1[i] > max2[i] then return false end
    if max1[i] < min2[i] then return false end
  end
  return true
end


local get_node, query_index

if ffi then

  get_node = function(tree, index)
    return index >= 0 and tree.nodes + index
  end

  query_leaf = function(tree, leaf, min, max, yield)
    leaf = tree.leaves - leaf - 1
    for i = leaf.first_item, leaf.last_item do
      local index = tree.items[i]
      if intersect_item(tree, min, max, tree:bounds(index)) then
        yield(tree, index)
      end
    end
  end

else

  get_node = function(tree, object)
    return object.axis and object
  end

  query_leaf = function(tree, leaf, min, max, yield)
    for _, index in ipairs(leaf) do
      if intersect_item(tree, min, max, tree:bounds(index)) then
        yield(tree, index)
      end
    end
  end

end


local query

local function query_node(tree, node, min, max, yield)
  if min[node.axis] <= node.split then
    query(tree, node.low,  min, max, yield)
  end
  if max[node.axis] >= node.split then
    query(tree, node.high, min, max, yield)
  end
  query(tree, node.mid, min, max, yield)
end


query = function(tree, object, min, max, yield)
  local node = get_node(tree, object)
  if node then
    query_node(tree, node, min, max, yield)
  else
    query_leaf(tree, object, min, max, yield)
  end
end


local function yield_index(tree, index)
  coroutine.yield(index)
end


local function yield_object(tree, index)
  coroutine.yield(tree.objects[index])
end


--- Query a kdtree.
--  Find all objects in the kdtree that intersect with the box defined by
--  min and max.
--  @return an iterator through the objects.  That is:
--
--      for o in mytree:query({1, 1}, {2, 2}) do
--        draw(o)
--      end
function kdtree:query(
  min,          -- table: minimum coordinates of the query box.
  max,          -- ?table: maximum coordinates of the query box (or nil if
                -- you want to query a point).
  yield)        -- ?function: the function to call for each object.
  max = max or min
  yield = yield or (self.objects and yield_object or yield_index)
  local root = self.root
  return coroutine.wrap(function() query(self, root, min, max, yield) end)
end


------------------------------------------------------------------------------

local write_text_count, write_text_leaf

if ffi then

  write_text_count = function(tree, o)
    o:write(("%d\t%d\t%d\n"):
      format(tree.node_count, tree.leaf_count, tree.item_count))
  end

  write_text_leaf = function(tree, o, leaf)
    leaf = tree.leaves - leaf - 1
    o:write(("L\t%d\n"):format(leaf.last_item - leaf.first_item + 1))
    for i = leaf.first_item, leaf.last_item do
      local index = tree.items[i]
      o:write(("%d\n"):format(index))
    end
  end

else

  local function count(tree, o)
    if o.axis then
      local n1, l1, i1 = count(tree, o.low)
      local n2, l2, i2 = count(tree, o.high)
      local n3, l3, i3 = count(tree, o.mid)

      return n1 + n2 + n3, l1 + l2 + l3, i1 + i2 + i3
    else
      return 0, 1, #o
    end
  end

  write_text_count = function(tree, o)
    o:write(("%d\t%d\t%d\n"):format(count(tree, tree.root)))
  end

  write_text_leaf = function(tree, o, leaf)
    o:write(("L\t%d\n"):format(#leaf))
    for _, index in ipairs(leaf) do
      o:write(("%d\n"):format(index))
    end
  end

end

local write_text

local function write_text_node(tree, o, node)
  o:write(("N\t%d\t%f\n"):format(node.axis, node.split))
  write_text(tree, o, node.low)
  write_text(tree, o, node.high)
  write_text(tree, o, node.mid)
end


write_text = function(tree, o, object)
  local node = get_node(tree, object)
  if node then write_text_node(tree, o, node)
  else write_text_leaf(tree, o, object)
  end
end


--- Write a kdtree to a text file.
--  The kdtree writes the *indexes* of the objects to the file.  It's up to
--  you to recover the objects when you read the kdtree.
function kdtree:write_text(
  filename)     -- string: the name of the file to write.
  local o = assert(io.open(filename, "w"))
  write_text_count(self, o)
  write_text(self, o, self.root)
  o:close()
end


------------------------------------------------------------------------------

local function read_text(tree, i)
  local l = i:read("*l")
  if l:match("^N") then
    local axis, split = l:match("N%s+(%d+)%s+(%S+)")
    axis = assert(tonumber(axis), "Axis is not a number")
    split = assert(tonumber(split), "Split coordinate is not a number")
    local low = read_text(tree, i)
    local high = read_text(tree, i)
    local mid = read_text(tree, i)
    return build_node(tree, axis, split, low, high, mid)
  elseif l:match("^L") then
    local c = l:match("L%s+(%d+)")
    c = assert(tonumber(c), "Item count is not a number")
    local leaf, ret = new_leaf(tree, c)
    for j = 1, c do
      local item = tonumber(i:read("*l"))
      add_to_leaf(tree, leaf, j, item)
    end
    return ret or leaf
  end
end


--- Read a kdtree from a text file.
--  This reads the *structure* of the tree.
--  It's up to you to pass in the objects that correspond to the indexes
--  in the tree if you wish to.
--  @treturn table: the kdtree
--  @see build
function kdtree.read_text(
  filename,     -- string: the name of the file to open.
  bounds,       -- function: as for build.
  dims,         -- ?integer: as for build.
  x,            -- ?integer|table: as for build.
  y)            -- ?integer: as for build.
  local i = io.open(filename, "r")

  local objects, leaf_size, wrapped_bounds
  if not x or type(x) == "number" then
    leaf_size = x
    wrapped_bounds = query_index_bounds
  else
    objects, leaf_size = x, y
    wrapped_bounds = query_object_bounds
  end

  local tree = init(bounds, dims, leaf_size)
  tree.objects = objects
  tree.bounds = wrapped_bounds

  local node_count, leaf_count, item_count =
    i:read("*n"), i:read("*n"), i:read("*n")
  i:read("*l")

  if ffi then
    tree.node_count, tree.leaf_count, tree.item_count = 0, 0, 0
    tree.node_limit, tree.leaf_limit = node_count, leaf_count

    tree.nodes = gcmalloc(node_count, "struct kdtree_node")
    tree.leaves = gcmalloc(leaf_count, "struct kdtree_leaf")
    tree.items = gcmalloc(item_count, "int32_t")
  end

  tree.root = read_text(tree, i)

  i:close()

  return tree
end


------------------------------------------------------------------------------

if lfs and mmapfile then

  --- Write a kdtree to a set of binary files.
  --  The kdtree writes the *indexes* of the objects to the files.  It's up
  --  to you to recover the objects when you read the kdtree.
  function kdtree:write_binary(
    dirname)    -- string: the name of the directory to write the files to.
                -- (write will create the directory)
    lfs.mkdir(dirname)
    mmapfile.gccreate(dirname.."/nodes",
      self.node_count, "struct kdtree_node", self.nodes)
    mmapfile.gccreate(dirname.."/leaves",
      self.leaf_count, "struct kdtree_leaf", self.leaves)
    mmapfile.gccreate(dirname.."/items",
      self.item_count, "int32_t", self.items)
  end


  --- Read a kdtree from a set of binary files.
  --  This reads the *structure* of the tree.
  --  It's up to you to pass in the objects that correspond to the indexes
  --  in the tree if you wish to.
  --  @treturn table: the kdtree
  --  @see build
  function kdtree.read_binary(
    dirname,    -- string: the name of the directory to read from.
    bounds,     -- function: as for build.
    dims,       -- ?integer: as for build.
    x,          -- ?integer|table: as for build.
    y)          -- ?integer: as for build.
    local objects, leaf_size, wrapped_bounds
    if not x or type(x) == "number" then
      leaf_size = x
      wrapped_bounds = query_index_bounds
    else
      objects, leaf_size = x, y
      wrapped_bounds = query_object_bounds
    end

    local tree = init(bounds, dims, leaf_size)

    tree.nodes, tree.node_count =
      mmapfile.gcopen(dirname.."/nodes", "struct kdtree_node")
    tree.leaves, tree.leaf_count =
      mmapfile.gcopen(dirname.."/leaves", "struct kdtree_leaf")
    tree.items, tree.item_count =
      mmapfile.gcopen(dirname.."/items", "int32_t")

    -- astonishingly, this works when the tree has so few items that there's no
    -- nodes, only one leaf.  In this case, the root becomes 0-1 = -1, which
    -- is the first (and only) leaf.
    -- I feel dirty leaving this here, but it's correct.
    tree.root = tree.node_count - 1

    tree.objects = objects
    tree.bounds = wrapped_bounds
    return tree
  end
end


------------------------------------------------------------------------------

return kdtree

------------------------------------------------------------------------------
