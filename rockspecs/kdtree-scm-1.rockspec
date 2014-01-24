package = "kdtree"
version = "scm-1"
source =
{
  url = "git://github.com/geoffleyland/lua-kdtree.git",
  branch = "master",
}
description =
{
  summary = "n-dimensional kdtree spatial index supporting boxes as well as points",
  homepage = "http://github.com/geoffleyland/lua-kdtree",
  license = "MIT/X11",
  maintainer = "Geoff Leyland <geoff.leyland@incremental.co.nz>"
}
dependencies =
{
  "lua >= 5.1"
}
build =
{
  type = "builtin",
  modules =
  {
    kdtree = "lua/kdtree.lua",
    ["kdtree.cdefs"] = "lua/kdtree/cdefs.lua"
  },
}
