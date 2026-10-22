///|
test "JSON strings escape quotes slashes control characters and keep Unicode" {
  assert_eq(
    json_string("a\"b\\c\n\r\t\u{0008}\u{000c}\u{0001}汉😀"),
    "\"a\\\"b\\\\c\\n\\r\\t\\b\\f\\u0001汉😀\"",
  )
}

///|
test "JSON exports represent optional review values as null" {
  let rows = [test_row("new.jpg", New, 123, destination=Some("new.jpg"))]
  let json = review_rows_json(rows)
  assert_true(json.contains("\"kind\":\"new\""))
  assert_true(json.contains("\"matchPath\":null"))
  assert_true(json.contains("\"similarityDistance\":null"))
  assert_true(json.contains("\"imageInfo\":null"))
  assert_true(json.contains("\"size\":123"))
}

///|
test "JSON exports escape filenames and include decoded metadata" {
  let info : ImageInfo = {
    width: 64,
    height: 48,
    luminance: 120,
    red: 100,
    green: 90,
    blue: 80,
  }
  let rows = [
    test_row(
      "incoming/a\"b\\c\n.jpg",
      New,
      88,
      destination=Some("photo.jpg"),
      image_info=Some(info),
    ),
  ]
  let json = review_rows_json(rows)
  assert_true(json.contains("a\\\"b\\\\c\\n.jpg"))
  assert_true(json.contains("\"width\":64"))
  assert_true(json.contains("\"height\":48"))
  assert_true(json.contains("\"blue\":80"))
}

///|
test "CSV fields quote delimiters line breaks and double quotes" {
  assert_eq(csv_field("plain"), "\"plain\"")
  assert_eq(csv_field("a,b"), "\"a,b\"")
  let quote = "\""
  assert_eq(
    csv_field("say \"yes\""),
    quote + "say " + quote + quote + "yes" + quote + quote + quote,
  )
  assert_eq(csv_field("line1\nline2"), "\"line1\nline2\"")
}

///|
test "CSV formula-like cells receive a text prefix while ordinary values stay exact" {
  assert_eq(csv_field("=1+1"), "\"'=1+1\"")
  assert_eq(csv_field("  @SUM(A1:A2)"), "\"'  @SUM(A1:A2)\"")
  assert_eq(csv_field("-photo.jpg"), "\"'-photo.jpg\"")
  assert_eq(csv_field("photo-1.jpg"), "\"photo-1.jpg\"")
  assert_eq(csv_field("   "), "\"   \"")
}

///|
test "review CSV carries stable columns and empty optional fields" {
  let rows = [test_row("a.jpg", Exact, 42, match_path=Some("old.jpg"))]
  let csv = review_rows_csv(rows)
  assert_true(csv.has_prefix("path,name,sha256,kind,match_path"))
  assert_true(
    csv.contains(
      "\"a.jpg\",\"a.jpg\",\"digest-a.jpg\",\"exact\",\"old.jpg\",\"\",\"\",\"42\",\"\"",
    ),
  )
  assert_true(csv.has_suffix("\r\n"))
}

///|
test "extension CSV quotes extension values and includes counts and bytes" {
  let items : Array[ExtensionStats] = [
    { extension: ".jpeg", count: 3, readable: 2, unreadable: 1, bytes: 999L, },
  ]
  let csv = extension_summary_csv(items)
  assert_true(csv.contains("\".jpeg\",3,2,1,999"))
}

///|
test "inventory JSON exports extension groups and every size band" {
  let photo = test_photo("one.jpg", "one.jpg", "same", None, 100)
  let photos = [photo]
  let summary = inventory_summary(photos)
  let json = inventory_json(
    summary,
    extension_summary(photos),
    size_distribution(photos),
  )
  assert_true(json.contains("\"total\":1"))
  assert_true(json.contains("\"unreadable\":1"))
  assert_true(json.contains("\"extension\":\".jpg\""))
  assert_true(json.contains("\"sizeBands\":["))
  assert_true(json.contains("\"duplicateExtraFiles\":0"))
}

///|
test "empty inventory export is valid JSON with empty extension list" {
  let json = inventory_json(inventory_summary([]), [], size_distribution([]))
  assert_eq(
    json, "{\"total\":0,\"readable\":0,\"unreadable\":0,\"bytes\":0,\"averageBytes\":0,\"dimensions\":{\"landscape\":0,\"portrait\":0,\"square\":0,\"unknown\":0},\"pixels\":0,\"duplicateFileGroups\":0,\"duplicateExtraFiles\":0,\"extensions\":[],\"sizeBands\":[{\"label\":\"小于 256 KiB\",\"count\":0,\"bytes\":0},{\"label\":\"256 KiB–1 MiB\",\"count\":0,\"bytes\":0},{\"label\":\"1–8 MiB\",\"count\":0,\"bytes\":0},{\"label\":\"8–32 MiB\",\"count\":0,\"bytes\":0},{\"label\":\"32 MiB 及以上\",\"count\":0,\"bytes\":0}]}",
  )
}
