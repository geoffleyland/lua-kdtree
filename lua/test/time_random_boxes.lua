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


local build_time, query_time = {}, {}


local function test(dims, box_count, query_count, leaf_low, leaf_high, leaf_step)
  io.stderr:write(("Testing %d dimensions\n"):format(dims))

  build_time[dims] = build_time[dims] or {}
  query_time[dims] = query_time[dims] or {}

  local boxes = {}
  for i = 1, box_count do
    boxes[i] = random_box(dims)
  end

  for leaf_size = leaf_low, leaf_high, leaf_step do

    local start = os.clock()
    local tree = kdtree.build(box_bounds, dims, boxes, leaf_size)
    build_time[dims][leaf_size] = (build_time[dims][leaf_size] or 0) + os.clock() - start

    local start = os.clock()
    local hits = 0
    for i = 1, query_count do
      local bounds = random_box(dims)
      for b in tree:query(bounds.min, bounds.max) do
        hits = hits + 1
      end
    end
    query_time[dims][leaf_size] = (query_time[dims][leaf_size] or 0) + os.clock() - start
    io.stderr:write(("Average response: %d%%\n"):format(hits / box_count / query_count * 100))
  end

end

for repetitions = 1, 2 do
  for d = 2, 5 do
    test(d, 1000, 1000, 10, 100, 10)
  end
end

for d = 2, 5 do
  for leaf_size = 10, 100, 10 do
    print(d, leaf_size, build_time[d][leaf_size], query_time[d][leaf_size])
  end
end
