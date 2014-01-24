local kdtree = require"kdtree"
local sqlite = require"lsqlite3"

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


local function test_lua_kdtree(tree_boxes, query_boxes)
  io.stderr:write("Testing Lua\n")
  local start = os.clock()
  local tree = kdtree.build(box_bounds, 2, tree_boxes)
  io.stderr:write(("Build time: %fs\n"):format(os.clock() - start))

  local results = 0
  local start = os.clock()
  for _, b in ipairs(query_boxes) do
    for b in tree:query(b.min, b.max) do
      results = results + 1
    end
  end
  io.stderr:write(("Query time: %.4fs, fill_rate: %.2f%%\n"):
    format(os.clock() - start, results / #tree_boxes / #query_boxes * 100))
end


local function test_sqlite(tree_boxes, query_boxes)
  io.stderr:write("Testing SQLite\n")

  local db = sqlite.open(":memory:")
  db:exec
  [[
    CREATE VIRTUAL TABLE boxes USING rtree(
      id,
      minX, maxX,
      minY, maxY);
  ]]

  local insert = db:prepare
  [[
    INSERT INTO boxes
      (id, minX, maxX, minY, maxY)
    VALUES
      (:id, :minX, :maxX, :minY, :maxY);
  ]]

  local query = db:prepare
  [[
    SELECT id FROM boxes
    WHERE
      maxX >= :minX AND minX <= :maxX AND
      maxY >= :minY AND minY <= :maxY;
  ]]

  local start = os.clock()
  db:exec("BEGIN")
  for i, b in ipairs(tree_boxes) do
    insert:bind_names{ id = i,
      minX = b.min[1], minY = b.min[2],
      maxX = b.max[1], maxY = b.max[2] }
    insert:step()
    insert:reset()
  end
  db:exec("COMMIT")
  io.stderr:write(("Build time: %fs\n"):format(os.clock() - start))

  local results = 0
  local start = os.clock()
  for _, b in ipairs(query_boxes) do
    query:bind_names{
      minX = b.min[1], minY = b.min[2],
      maxX = b.max[1], maxY = b.max[2] }
    for id in query:urows() do
      results = results + 1
    end
    query:reset()
  end
  io.stderr:write(("Query time: %.4fs, fill_rate: %.2f%%\n"):
    format(os.clock() - start, results / #tree_boxes / #query_boxes * 100))
end


local function test(box_count, query_count)
  local tree_boxes = {}
  for i = 1, box_count do
    tree_boxes[i] = random_box(2)
  end

  local query_boxes = {}
  for i = 1, query_count do
    query_boxes[i] = random_box(2)
  end

  test_lua_kdtree(tree_boxes, query_boxes)
  test_sqlite(tree_boxes, query_boxes)
end

test(1000000, 100)
