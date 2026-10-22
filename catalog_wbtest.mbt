///|
test "normalized extension uses the final path component and ignores case" {
  assert_eq(normalized_extension("folder\\Trip.JPEG"), ".jpeg")
  assert_eq(normalized_extension("folder/photo.PNG"), ".png")
  assert_eq(normalized_extension("README"), "(无扩展名)")
  assert_eq(normalized_extension("folder/.hidden"), "(无扩展名)")
  assert_eq(normalized_extension("folder/photo."), "(无扩展名)")
}

///|
test "size bands include exact lower bounds and exclude upper bounds" {
  assert_true(size_band(-1) == Under256KiB)
  assert_true(size_band(262143) == Under256KiB)
  assert_true(size_band(262144) == From256KiBTo1MiB)
  assert_true(size_band(1048575) == From256KiBTo1MiB)
  assert_true(size_band(1048576) == From1MiBTo8MiB)
  assert_true(size_band(8388608) == From8MiBTo32MiB)
  assert_true(size_band(33554432) == AtLeast32MiB)
  assert_eq(AtLeast32MiB.label(), "32 MiB 及以上")
}

///|
test "empty inventory has zero totals and does not invent a minimum" {
  let summary = inventory_summary([])
  assert_eq(summary.total, 0)
  assert_eq(summary.bytes, 0L)
  assert_eq(summary.minimum_size, 0)
  assert_eq(summary.average_size, 0L)
  assert_eq(summary.duplicate_file_groups, 0)
  assert_eq(summary.duplicate_files, 0)
}

///|
test "inventory counts orientations, decoded pixels, bytes and duplicate extras" {
  let landscape : ImageInfo = {
    width: 1920,
    height: 1080,
    luminance: 120,
    red: 90,
    green: 90,
    blue: 90,
  }
  let portrait : ImageInfo = {
    width: 900,
    height: 1200,
    luminance: 130,
    red: 100,
    green: 100,
    blue: 100,
  }
  let photos = [
    test_photo(
      "a.jpg",
      "a.jpg",
      "same",
      Some("0".repeat(176)),
      100,
      image_info=Some(landscape),
    ),
    test_photo(
      "b.jpg",
      "b.jpg",
      "same",
      Some("1".repeat(176)),
      300,
      image_info=Some(landscape),
    ),
    test_photo("c.png", "c.png", "unique", None, 500, image_info=Some(portrait)),
    test_photo("bad.png", "bad.png", "broken", None, 50),
  ]
  let summary = inventory_summary(photos)
  assert_eq(summary.total, 4)
  assert_eq(summary.readable, 3)
  assert_eq(summary.unreadable, 1)
  assert_eq(summary.bytes, 950L)
  assert_eq(summary.minimum_size, 50)
  assert_eq(summary.maximum_size, 500)
  assert_eq(summary.average_size, 237L)
  assert_eq(summary.landscape, 2)
  assert_eq(summary.portrait, 1)
  assert_eq(summary.square, 0)
  assert_eq(summary.unknown_dimensions, 1)
  assert_eq(summary.pixels, 2L * (1920L * 1080L) + 900L * 1200L)
  assert_eq(summary.duplicate_file_groups, 1)
  assert_eq(summary.duplicate_files, 1)
}

///|
test "duplicate groups preserve all paths and count only copies beyond the first" {
  let photos = [
    test_photo("in/a.jpg", "a.jpg", "x", None, 4),
    test_photo("library/b.jpg", "b.jpg", "y", None, 9),
    test_photo("in/c.jpg", "c.jpg", "x", None, 4),
    test_photo("in/d.jpg", "d.jpg", "x", None, 4),
  ]
  let groups = duplicate_digest_groups(photos)
  assert_eq(groups.length(), 1)
  assert_eq(groups[0].digest, "x")
  assert_eq(groups[0].paths, ["in/a.jpg", "in/c.jpg", "in/d.jpg"])
  assert_eq(groups[0].bytes, 12L)
}

///|
test "extension statistics are sorted and distinguish decodable from unreadable" {
  let info : ImageInfo = {
    width: 10,
    height: 10,
    luminance: 80,
    red: 80,
    green: 80,
    blue: 80,
  }
  let photos = [
    test_photo(
      "a/z.PNG",
      "z.PNG",
      "a",
      Some("0".repeat(64)),
      100,
      image_info=Some(info),
    ),
    test_photo("a/a.JPG", "a.JPG", "b", None, 200),
    test_photo(
      "a/b.jpeg",
      "b.jpeg",
      "c",
      Some("0".repeat(64)),
      300,
      image_info=Some(info),
    ),
    test_photo("a/noext", "noext", "d", None, 400),
  ]
  let stats = extension_summary(photos)
  assert_eq(stats.length(), 4)
  assert_eq(stats[0].extension, ".jpeg")
  assert_eq(stats[0].readable, 1)
  assert_eq(stats[1].extension, ".jpg")
  assert_eq(stats[1].unreadable, 1)
  assert_eq(stats[2].extension, ".png")
  assert_eq(stats[3].extension, "(无扩展名)")
  assert_eq(stats[3].bytes, 400L)
}

///|
test "size distribution includes empty bands and totals every photo once" {
  let photos = [
    test_photo("a", "a.jpg", "a", None, 0),
    test_photo("b", "b.jpg", "b", None, 262144),
    test_photo("c", "c.jpg", "c", None, 1048576),
    test_photo("d", "d.jpg", "d", None, 8388608),
    test_photo("e", "e.jpg", "e", None, 33554432),
  ]
  let bands = size_distribution(photos)
  assert_eq(bands.length(), 5)
  assert_eq(bands[0].count, 1)
  assert_eq(bands[1].count, 1)
  assert_eq(bands[2].count, 1)
  assert_eq(bands[3].count, 1)
  assert_eq(bands[4].count, 1)
  assert_eq(bands[4].bytes, 33554432L)
}

///|
test "plan summary counts review work and safe copy bytes" {
  let rows = [
    test_row("new.jpg", New, 100, destination=Some("new.jpg")),
    test_row(
      "similar.jpg",
      Similar,
      200,
      destination=Some("similar.jpg"),
      distance=Some(2),
    ),
    test_row(
      "conflict.jpg",
      Conflict,
      300,
      destination=Some("conflict-import-1.jpg"),
    ),
    test_row("exact.jpg", Exact, 400),
    test_row("bad.jpg", Unreadable, 500),
  ]
  let summary = plan_summary(rows)
  assert_eq(summary.total, 5)
  assert_eq(summary.exact, 1)
  assert_eq(summary.similar, 1)
  assert_eq(summary.conflict, 1)
  assert_eq(summary.new_count, 1)
  assert_eq(summary.unreadable, 1)
  assert_eq(summary.copyable, 3)
  assert_eq(summary.needs_review, 2)
  assert_eq(summary.selected_by_default, 1)
  assert_eq(summary.total_bytes, 1500L)
  assert_eq(summary.copyable_bytes, 600L)
  assert_eq(summary.review_bytes, 500L)
}

///|
test "plan summary does not count exact and unreadable items as copyable" {
  let rows = [
    test_row("same.jpg", Exact, 99),
    test_row("broken.jpg", Unreadable, 101),
  ]
  let summary = plan_summary(rows)
  assert_eq(summary.copyable, 0)
  assert_eq(summary.copyable_bytes, 0L)
  assert_eq(summary.review_bytes, 0L)
}

///|
test "image notes describe visible observations at documented boundaries" {
  let dark_wide : ImageInfo = {
    width: 1800,
    height: 400,
    luminance: 23,
    red: 200,
    green: 60,
    blue: 40,
  }
  let notes = image_review_notes(dark_wide)
  assert_eq(notes.length(), 4)
  assert_eq(notes[0], "分辨率较小")
  assert_eq(notes[1], "长宽比例较大")
  assert_eq(notes[2], "整体偏暗")
  assert_eq(notes[3], "平均颜色偏向单一色调")
  let small_bright : ImageInfo = {
    width: 639,
    height: 639,
    luminance: 233,
    red: 100,
    green: 100,
    blue: 100,
  }
  assert_eq(image_review_notes(small_bright), [
    "分辨率较小", "整体偏亮",
  ])
}

///|
test "metadata labels include dimensions without implying confidence" {
  let info : ImageInfo = {
    width: 4000,
    height: 3000,
    luminance: 100,
    red: 100,
    green: 100,
    blue: 100,
  }
  assert_true(image_info_label(info).contains("4000 × 3000"))
  assert_true(image_info_label(info).contains("12.0 MP"))
  assert_eq(format_bytes(900L), "900 B")
  assert_eq(format_bytes(1024L), "1.0 KiB")
}
