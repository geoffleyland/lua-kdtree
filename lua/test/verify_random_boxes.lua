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


local function intersect(dims, min1, max1, min2, max2)
  for i = 1, dims do
    if min1[i] > max2[i] then return false end
    if max1[i] < min2[i] then return false end
  end
  return true
end


local function test(dims, box_count, query_count)
  io.stderr:write(("Testing %d dimensions\n"):format(dims))
  local boxes = {}
  for i = 1, box_count do
    boxes[i] = random_box(dims)
  end

  local tree = kdtree.build(box_bounds, dims, boxes)

  local hits = 0
  for i = 1, query_count do
    local results = {}
    local bounds = random_box(dims)
    for b in tree:query(bounds.min, bounds.max) do
      results[b] = true
      hits = hits + 1
      for d = 1, dims do
        assert(b.min[d] <= bounds.max[d])
        assert(b.max[d] >= bounds.min[d])
      end
    end
    for _, b in ipairs(boxes) do
      assert(results[b] or not intersect(dims, b.min, b.max, bounds.min, bounds.max))
    end
  end

  io.stderr:write(("Average response: %d%%\n"):format(hits / box_count / query_count * 100))
end

for d = 2, 5 do
  test(d, 1000, 1000)
end

