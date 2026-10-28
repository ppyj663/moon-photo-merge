// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "ppyj663/photo_merge"

version = "0.1.1"

readme = "README.md"

repository = "https://github.com/ppyj663/moon-photo-merge"

license = "Apache-2.0"

keywords = [ "photo", "backup", "image", "deduplication" ]

preferred_target = "js"

supported_targets = "js"

description = "Review-first photo backup merge tool with exact and visual comparison"

import {
  "gmlewis/image@0.17.18",
  "gmlewis/io@0.23.20",
}
