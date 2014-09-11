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

local function malloc(size, type)
  if type then size = size * ffi.sizeof(type) end
  local addr = ffi.C.malloc(size)
  if type then
    return ffi.cast(type.."*", addr)
  else
    return addr
  end
end


local function gcmalloc(size, type)
  return ffi.gc(malloc(size, type), ffi.C.free)
end


local function free(ptr)
  ffi.C.free(ffi.cast("void *", ptr))
end


------------------------------------------------------------------------------

return { malloc = malloc, gcmalloc = gcmalloc, free = free }

------------------------------------------------------------------------------
