///|
fn scan_folder(root : String, prefix : String) -> Array[@lib.Photo] {
  let photos : Array[@lib.Photo] = []
  for relative in image_files(root) {
    let bytes = read_photo(root, relative)
    let digest = sha256_bytes(bytes)
    let photo : @lib.Photo = {
      path: prefix + "/" + relative,
      name: file_name(relative),
      digest,
      fingerprint: @lib.fingerprint(bytes, file_ext(relative)),
      size: bytes.length(),
    }
    photos.push(photo)
  }
  photos
}

///|
fn scan_id(
  library : String,
  incoming : String,
  existing : Array[@lib.Photo],
  fresh : Array[@lib.Photo],
  similar_limit : Int32,
) -> String {
  let mut content = "photo-merge-v2\n" +
    library +
    "\n" +
    incoming +
    "\nsimilar-limit=" +
    similar_limit.to_string() +
    "\n"
  for photo in existing {
    content = content +
      photo.path +
      "\t" +
      photo.digest +
      "\t" +
      photo.size.to_string() +
      "\n"
  }
  for photo in fresh {
    content = content +
      photo.path +
      "\t" +
      photo.digest +
      "\t" +
      photo.size.to_string() +
      "\n"
  }
  sha256_text(content)
}

///|
fn optional_text(value : String?) -> String {
  match value {
    Some(text) => text
    None => ""
  }
}

///|
fn optional_distance(value : Int32?) -> String {
  match value {
    Some(distance) => distance.to_string()
    None => ""
  }
}

///|
fn make_report(
  library : String,
  incoming : String,
  rows : Array[@lib.ReviewRow],
  id : String,
  similar_limit : Int32,
) -> String {
  let mut table = ""
  let mut exact = 0
  let mut similar = 0
  let mut conflict = 0
  let mut new_count = 0
  let mut unreadable = 0
  for row in rows {
    match row.kind {
      Exact => exact = exact + 1
      Similar => similar = similar + 1
      Conflict => conflict = conflict + 1
      New => new_count = new_count + 1
      Unreadable => unreadable = unreadable + 1
    }
    let match_path = optional_text(row.match_path)
    table = table +
      html_row(
        row.path,
        row.kind.label(),
        row.kind.code(),
        match_path,
        optional_distance(row.similarity_distance),
        optional_text(row.destination),
        row.size,
        image_url(incoming, incoming_relative(row.path)),
        match_url(match_path, library, incoming),
      )
  }
  html_page(
    id,
    table,
    rows.length(),
    exact,
    similar,
    conflict,
    new_count,
    unreadable,
    similar_limit,
  )
}

///|
fn fail(message : String) -> Unit {
  println("错误：" + message)
  set_exit_code(2)
}

///|
fn print_usage() -> Unit {
  println("用法：")
  println(
    "  moon run cmd/main -- scan <现有相册> <待导入备份> <报告文件夹> [--similarity-limit 0..176]",
  )
  println(
    "  moon run cmd/main -- apply <现有相册> <待导入备份> <approved.json> [--similarity-limit 0..176]",
  )
  println("  moon run cmd/main -- --help")
}

///|
fn parse_similarity_limit(args : FixedArray[String]) -> (Int32, String) {
  if args.length() == 4 {
    return (5, "")
  }
  if args.length() != 6 || args[4] != "--similarity-limit" {
    return (5, "可选参数格式为 --similarity-limit 0..176")
  }
  let raw = args[5]
  if raw.length() == 0 {
    return (5, "相似阈值必须是 0 到 176 的整数")
  }
  let mut parsed = 0
  for index = 0; index < raw.length(); index = index + 1 {
    let digit = match raw[index] {
      '0' => 0
      '1' => 1
      '2' => 2
      '3' => 3
      '4' => 4
      '5' => 5
      '6' => 6
      '7' => 7
      '8' => 8
      '9' => 9
      _ => -1
    }
    if digit < 0 {
      return (5, "相似阈值必须是 0 到 176 的整数")
    }
    parsed = parsed * 10 + digit
    if parsed > 176 {
      return (5, "相似阈值范围是 0 到 176")
    }
  }
  (parsed, "")
}

///|
fn main {
  let args = cli_args()
  if args.length() == 1 && (args[0] == "--help" || args[0] == "-h") {
    print_usage()
    return
  }
  let invalid_count = args.length() != 4 && args.length() != 6
  let invalid_command = args[0] != "scan" && args[0] != "apply"
  if invalid_count || invalid_command {
    print_usage()
    set_exit_code(2)
    return
  }
  let (similar_limit, limit_error) = parse_similarity_limit(args)
  if limit_error != "" {
    fail(limit_error)
    return
  }
  let library = args[1]
  let incoming = args[2]
  let third = args[3]
  let report_folder = if args[0] == "scan" { third } else { file_parent(third) }
  let invalid = validate_paths(library, incoming, report_folder)
  if invalid != "" {
    fail(invalid)
    return
  }
  let library = real_path(library)
  let incoming = real_path(incoming)
  let existing = scan_folder(library, "library")
  let fresh = scan_folder(incoming, "incoming")
  let rows = @lib.build_plan(existing, fresh, similar_limit~)
  let id = scan_id(library, incoming, existing, fresh, similar_limit)
  if args[0] == "scan" {
    let error = write_report(
      third,
      make_report(library, incoming, rows, id, similar_limit),
    )
    if error != "" {
      fail(error)
      return
    }
    println(
      "预检完成：" + rows.length().to_string() + " 张待导入图片",
    )
    println("报告：" + report_path(third))
    return
  }
  let approval_error = approved_error(third)
  if approval_error != "" {
    fail(approval_error)
    return
  }
  if approved_scan_id(third) != id {
    fail(
      "审核清单与当前相册或备份不一致；请重新运行 scan 并审核",
    )
    return
  }
  let selected = approved_paths(third)
  let chosen : Map[String, Bool] = Map([])
  for path in selected {
    if chosen.get(path) is Some(_) {
      fail("审核清单含有重复路径：" + path)
      return
    }
    let mut found = false
    for row in rows {
      if row.path == path {
        found = true
        if row.destination is None {
          fail("审核清单选中了不可复制的文件：" + path)
          return
        }
        break
      }
    }
    if !found {
      fail("审核清单路径不存在：" + path)
      return
    }
    chosen.set(path, true)
  }
  let mut copied = 0
  for row in rows {
    if chosen.get(row.path) is Some(_) {
      let destination = optional_text(row.destination)
      let error = safe_copy(
        incoming,
        incoming_relative(row.path),
        library,
        destination,
        row.digest,
      )
      if error != "" {
        fail(row.path + " 复制失败：" + error)
        return
      }
      println("已复制：" + row.path + " → " + destination)
      copied = copied + 1
    }
  }
  println(
    "完成：复制 " +
    copied.to_string() +
    " 张；未删除或覆盖原文件",
  )
}
