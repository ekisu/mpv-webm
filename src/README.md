Due to the way the build script works, .moon files inside this dir will get bundled together as a big .moon file, which will then be compiled to .lua.

This means no "require"s are needed between files here, as they will behave as they were on the same file. However, the order in which the sources will be included does matter. This order is described inside the Makefile in the root directory.

Also, ensure every file has an empty line in the end, or the bundled .moon file will probably be broken.
