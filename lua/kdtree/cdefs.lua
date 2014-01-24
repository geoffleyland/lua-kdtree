local ffi = require"ffi"


ffi.cdef
[[
void *malloc(size_t);
void free(void *);

struct kdtree_event
{
  double x;
  int32_t type, item;
};
struct kdtree_node
{
  double split;
  int32_t axis, low, mid, high;
};
struct kdtree_leaf
{
  int32_t first_item, last_item;
};
]]


------------------------------------------------------------------------------

local function malloc(type, size)
  return ffi.cast(type.."*", ffi.C.malloc(size * ffi.sizeof(type)))
end


local function gcmalloc(type, size)
  return ffi.gc(malloc(type, size), ffi.C.free)
end


local function free(ptr)
  ffi.C.free(ffi.cast("void *", ptr))
end


------------------------------------------------------------------------------

return { malloc = malloc, gcmalloc = gcmalloc, free = free }

------------------------------------------------------------------------------
