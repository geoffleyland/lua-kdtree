local kdtree = require"kdtree"

local function random_box(dims)
  local min, max = {}, {}
  for i = 1, dims do
    local centre, span = math.random(), math.random() / 2
    min[i], max[i] = centre - span, centre + span
  end
  return { min = min, max = max }
end


local function box_bounds(b)
  return b.min, b.max
end


local function test(dims, box_count, query_count)
  io.stderr:write(("Testing %d dimensions\n"):format(dims))
  local boxes = {}
  for i = 1, box_count do
    boxes[i] = random_box(dims)
  end

  local tree = kdtree.build(box_bounds, dims, boxes)
  tree:write_binary("binary-file-test")
  local tree2 = kdtree.read_binary("binary-file-test", box_bounds, dims, boxes)

  for i = 1, query_count do
    local results = {}
    local bounds = random_box(dims)
    for b in tree:query(bounds.min, bounds.max) do
      results[b] = 1
    end
    for b in tree2:query(bounds.min, bounds.max) do
      assert(results[b] == 1)
      results[b] = 2
    end
    for _, v in pairs(results) do assert(v == 2) end
  end
end

test(2, 10000, 1000)
