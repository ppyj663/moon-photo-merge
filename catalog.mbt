///|
/// A byte-size band used by the inventory summary.
pub(all) enum SizeBand {
  Under256KiB
  From256KiBTo1MiB
  From1MiBTo8MiB
  From8MiBTo32MiB
  AtLeast32MiB
} derive(Eq)

///|
pub extend SizeBand with Eq::{not_equal, equal}

///|
pub fn SizeBand::label(self : SizeBand) -> String {
  match self {
    Under256KiB => "小于 256 KiB"
    From256KiBTo1MiB => "256 KiB–1 MiB"
    From1MiBTo8MiB => "1–8 MiB"
    From8MiBTo32MiB => "8–32 MiB"
    AtLeast32MiB => "32 MiB 及以上"
  }
}

///|
pub(all) struct SizeBandStats {
  band : SizeBand
  count : Int32
  bytes : Int64
}

///|
pub(all) struct ExtensionStats {
  extension : String
  count : Int32
  readable : Int32
  unreadable : Int32
  bytes : Int64
}

///|
pub(all) struct InventorySummary {
  total : Int32
  readable : Int32
  unreadable : Int32
  bytes : Int64
  minimum_size : Int32
  maximum_size : Int32
  average_size : Int64
  landscape : Int32
  portrait : Int32
  square : Int32
  unknown_dimensions : Int32
  pixels : Int64
  duplicate_file_groups : Int32
  duplicate_files : Int32
}

///|
pub(all) struct PlanSummary {
  total : Int32
  exact : Int32
  similar : Int32
  conflict : Int32
  new_count : Int32
  unreadable : Int32
  copyable : Int32
  needs_review : Int32
  selected_by_default : Int32
  total_bytes : Int64
  copyable_bytes : Int64
  review_bytes : Int64
}

///|
pub(all) struct DigestGroup {
  digest : String
  paths : Array[String]
  bytes : Int64
}

///|
fn extension_of(name : String) -> String {
  match name.rev_split_once(".") {
    Some((stem, extension)) if stem.length() > 0 && extension.length() > 0 =>
      "." + extension.to_lower().to_owned()
    _ => "(无扩展名)"
  }
}

///|
/// Normalize path separators before extracting a final component. The
/// collection API otherwise treats paths as opaque labels.
pub fn normalized_extension(name : String) -> String {
  let mut start = 0
  for index = 0; index < name.length(); index = index + 1 {
    if name[index] == '/' || name[index] == '\\' {
      start = index + 1
    }
  }
  extension_of(name.view(start_offset=start).to_owned())
}

///|
pub fn size_band(size : Int32) -> SizeBand {
  if size < 256 * 1024 {
    Under256KiB
  } else if size < 1024 * 1024 {
    From256KiBTo1MiB
  } else if size < 8 * 1024 * 1024 {
    From1MiBTo8MiB
  } else if size < 32 * 1024 * 1024 {
    From8MiBTo32MiB
  } else {
    AtLeast32MiB
  }
}

///|
fn add_bytes(left : Int64, right : Int32) -> Int64 {
  left + right.to_int64()
}

///|
fn empty_inventory() -> InventorySummary {
  {
    total: 0,
    readable: 0,
    unreadable: 0,
    bytes: 0L,
    minimum_size: 0,
    maximum_size: 0,
    average_size: 0L,
    landscape: 0,
    portrait: 0,
    square: 0,
    unknown_dimensions: 0,
    pixels: 0L,
    duplicate_file_groups: 0,
    duplicate_files: 0,
  }
}

///|
/// Return groups of byte-identical files. Group order follows first appearance
/// in the input, and path order follows the input order as well.
pub fn duplicate_digest_groups(photos : Array[Photo]) -> Array[DigestGroup] {
  let digest_indices : Map[String, Int32] = Map([])
  let groups : Array[DigestGroup] = []
  for photo in photos {
    match digest_indices.get(photo.digest) {
      Some(group_index) => {
        let previous = groups[group_index]
        previous.paths.push(photo.path)
        groups[group_index] = {
          digest: previous.digest,
          paths: previous.paths,
          bytes: previous.bytes + photo.size.to_int64(),
        }
      }
      None => {
        digest_indices.set(photo.digest, groups.length())
        groups.push({
          digest: photo.digest,
          paths: [photo.path],
          bytes: photo.size.to_int64(),
        })
      }
    }
  }
  let duplicates : Array[DigestGroup] = []
  for group in groups {
    if group.paths.length() > 1 {
      duplicates.push(group)
    }
  }
  duplicates
}

///|
/// Summarize a folder scan without changing the photos or their order.
pub fn inventory_summary(photos : Array[Photo]) -> InventorySummary {
  if photos.length() == 0 {
    return empty_inventory()
  }
  let mut bytes = 0L
  let mut minimum = photos[0].size
  let mut maximum = photos[0].size
  let mut readable = 0
  let mut unreadable = 0
  let mut landscape = 0
  let mut portrait = 0
  let mut square = 0
  let mut pixels = 0L
  for photo in photos {
    bytes = add_bytes(bytes, photo.size)
    minimum = minimum.min(photo.size)
    maximum = maximum.max(photo.size)
    match photo.image_info {
      Some(info) => {
        readable = readable + 1
        pixels = pixels + info.width.to_int64() * info.height.to_int64()
        if info.width > info.height {
          landscape = landscape + 1
        } else if info.height > info.width {
          portrait = portrait + 1
        } else {
          square = square + 1
        }
      }
      None => unreadable = unreadable + 1
    }
  }
  let duplicate_groups = duplicate_digest_groups(photos)
  let mut duplicate_files = 0
  for group in duplicate_groups {
    duplicate_files = duplicate_files + group.paths.length() - 1
  }
  {
    total: photos.length(),
    readable,
    unreadable,
    bytes,
    minimum_size: minimum,
    maximum_size: maximum,
    average_size: bytes / photos.length().to_int64(),
    landscape,
    portrait,
    square,
    unknown_dimensions: unreadable,
    pixels,
    duplicate_file_groups: duplicate_groups.length(),
    duplicate_files,
  }
}

///|
/// Aggregate photo count, decoded count and bytes by normalized extension.
/// Output is sorted alphabetically for reproducible reports.
pub fn extension_summary(photos : Array[Photo]) -> Array[ExtensionStats] {
  let extension_indices : Map[String, Int32] = Map([])
  let result : Array[ExtensionStats] = []
  for photo in photos {
    let extension = normalized_extension(photo.name)
    match extension_indices.get(extension) {
      Some(index) => {
        let previous = result[index]
        let readable = match photo.image_info {
          Some(_) => 1
          None => 0
        }
        let unreadable = 1 - readable
        result[index] = {
          extension,
          count: previous.count + 1,
          readable: previous.readable + readable,
          unreadable: previous.unreadable + unreadable,
          bytes: previous.bytes + photo.size.to_int64(),
        }
      }
      None => {
        let readable = match photo.image_info {
          Some(_) => 1
          None => 0
        }
        extension_indices.set(extension, result.length())
        result.push({
          extension,
          count: 1,
          readable,
          unreadable: 1 - readable,
          bytes: photo.size.to_int64(),
        })
      }
    }
  }
  result.sort_by((left, right) => {
    if left.extension == "(无扩展名)" && right.extension != "(无扩展名)" {
      1
    } else if right.extension == "(无扩展名)" &&
      left.extension != "(无扩展名)" {
      -1
    } else if left.extension.lexical_compare(right.extension) < 0 {
      -1
    } else if left.extension.lexical_compare(right.extension) > 0 {
      1
    } else {
      0
    }
  })
  result
}

///|
fn empty_size_bands() -> Array[SizeBandStats] {
  [
    { band: Under256KiB, count: 0, bytes: 0L, },
    { band: From256KiBTo1MiB, count: 0, bytes: 0L, },
    { band: From1MiBTo8MiB, count: 0, bytes: 0L, },
    { band: From8MiBTo32MiB, count: 0, bytes: 0L, },
    { band: AtLeast32MiB, count: 0, bytes: 0L, },
  ]
}

///|
/// Count files and total bytes in fixed, documented size ranges.
pub fn size_distribution(photos : Array[Photo]) -> Array[SizeBandStats] {
  let result = empty_size_bands()
  for photo in photos {
    let index = match size_band(photo.size) {
      Under256KiB => 0
      From256KiBTo1MiB => 1
      From1MiBTo8MiB => 2
      From8MiBTo32MiB => 3
      AtLeast32MiB => 4
    }
    let previous = result[index]
    result[index] = {
      band: previous.band,
      count: previous.count + 1,
      bytes: previous.bytes + photo.size.to_int64(),
    }
  }
  result
}

///|
/// Counts and byte totals for the incoming review plan.
pub fn plan_summary(rows : Array[ReviewRow]) -> PlanSummary {
  let mut exact = 0
  let mut similar = 0
  let mut conflict = 0
  let mut new_count = 0
  let mut unreadable = 0
  let mut copyable = 0
  let mut needs_review = 0
  let mut selected_by_default = 0
  let mut total_bytes = 0L
  let mut copyable_bytes = 0L
  let mut review_bytes = 0L
  for row in rows {
    total_bytes = total_bytes + row.size.to_int64()
    match row.kind {
      Exact => exact = exact + 1
      Similar => {
        similar = similar + 1
        needs_review = needs_review + 1
        review_bytes = review_bytes + row.size.to_int64()
      }
      Conflict => {
        conflict = conflict + 1
        needs_review = needs_review + 1
        review_bytes = review_bytes + row.size.to_int64()
      }
      New => {
        new_count = new_count + 1
        selected_by_default = selected_by_default + 1
        copyable = copyable + 1
        copyable_bytes = copyable_bytes + row.size.to_int64()
      }
      Unreadable => unreadable = unreadable + 1
    }
    if row.destination is Some(_) && row.kind != New {
      copyable = copyable + 1
      copyable_bytes = copyable_bytes + row.size.to_int64()
    }
  }
  {
    total: rows.length(),
    exact,
    similar,
    conflict,
    new_count,
    unreadable,
    copyable,
    needs_review,
    selected_by_default,
    total_bytes,
    copyable_bytes,
    review_bytes,
  }
}

///|
/// Format a byte count using binary units. The output is intended for reports,
/// not as a machine-readable value.
pub fn format_bytes(bytes : Int64) -> String {
  if bytes < 1024L {
    bytes.to_string() + " B"
  } else if bytes < 1048576L {
    format_tenths(bytes, 1024L) + " KiB"
  } else if bytes < 1073741824L {
    format_tenths(bytes, 1048576L) + " MiB"
  } else {
    format_tenths(bytes, 1073741824L) + " GiB"
  }
}

///|
fn format_tenths(value : Int64, divisor : Int64) -> String {
  let tenths = (value * 10L + divisor / 2L) / divisor
  (tenths / 10L).to_string() + "." + (tenths % 10L).to_string()
}

///|
/// Explain a few visible characteristics that can help a person compare a
/// questionable file. These are observations, not quality verdicts.
pub fn image_review_notes(info : ImageInfo) -> Array[String] {
  let notes : Array[String] = []
  if info.width < 640 || info.height < 640 {
    notes.push("分辨率较小")
  }
  let shorter = info.width.min(info.height).max(1)
  let longer = info.width.max(info.height)
  if longer > shorter * 3 {
    notes.push("长宽比例较大")
  }
  if info.luminance < 24 {
    notes.push("整体偏暗")
  } else if info.luminance > 232 {
    notes.push("整体偏亮")
  }
  let max_color = info.red.max(info.green).max(info.blue)
  let min_color = info.red.min(info.green).min(info.blue)
  if max_color - min_color > 96 {
    notes.push("平均颜色偏向单一色调")
  }
  notes
}

///|
/// Present decoded dimensions and approximate megapixels in one short label.
pub fn image_info_label(info : ImageInfo) -> String {
  let megapixels = (info.width.to_int64() * info.height.to_int64() + 50000L) /
    100000L
  let megapixels_text = (megapixels / 10L).to_string() +
    "." +
    (megapixels % 10L).to_string()
  info.width.to_string() +
  " × " +
  info.height.to_string() +
  " · " +
  megapixels_text +
  " MP"
}
