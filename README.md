# Lua-kdtree - n-dimensional kdtree spatial indexing.

## 1. What?

A [kdtree](http://en.wikipedia.org/wiki/K-d_tree) is a data structure
for quickly finding out what objects in space intersect with a given query
volume.

This implements a read-only n-dimensional kdtree that can contain boxes
as well as points.

Read-only means that you build the kdtree once on a large set of data,
and query many times on that data set.  Once the kdtree is built, you
can't add objects to it.  This could be extended, but it's all I need
for the moment.

N-dimensional means that the kdtree works on 2D-spaces (like road maps),
a 3D spaces, and higher dimensional spaces.  At higher dimensions,
spatial querying makes less and less sense though.

The objects in the kdtree can be boxes as well as points.  I don't know
why, but many of the implementations I've can only contain points.

The kdtree can be written to a file.  This can be a text file, or, if
you're using [LuaJIT](http://luajit.org),
and have [ljsycall](https://github.com/justincormack/ljsyscall)
and [lua-mmapfile](https://github.com/geoffleyland/lua-mmapfile),
a binary file.


## 2. How?
Either

    git clone git@github.com:geoffleyland/lua-kdtree.git
    cd lua-kdtree
    make install

or, once the rockspec's up `luarocks install kdtree`.  Then:

    local kdtree = require"kdtree"

    local my_objects = -- make some objects

    local function my_bounds(o, min, max)
      min[1], min[2] = o.left, o.bottom
      max[1], max[2] = o.right, o.top
      return min, max
    end

    local tree = kdtree.build(my_bounds, 2, my_objects)

    for o in tree:query({1, 1}, {2, 2}) do
      print("Found", tostring(o))
    end


## 3. Requirements

Lua >= 5.1 or LuaJIT >= 2.0.0, ljsyscall and lua-mapfile for binary file io.


## 4. Issues

+ The argument list to `build` is horrible.
+ It would be good to be able to hold object ids (64 bit integers) directly
+ in the tree.


## 5. Wishlist

+ Read-write kdtrees?
+ A bit of speed work using leaf and node bounds (a few experiments with
  these didn't make much progress)


## 6. Alternatives

+ SQLite and PostGres have spatial indexing capabilities
