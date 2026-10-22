///|
fn json_hex_digit(value : Int32) -> Char {
  match value {
    0 => '0'
    1 => '1'
    2 => '2'
    3 => '3'
    4 => '4'
    5 => '5'
    6 => '6'
    7 => '7'
    8 => '8'
    9 => '9'
    10 => 'a'
    11 => 'b'
    12 => 'c'
    13 => 'd'
    14 => 'e'
    _ => 'f'
  }
}

///|
/// Quote a string as a JSON value, including control characters and Unicode.
pub fn json_string(value : String) -> String {
  let output = StringBuilder()
  output.write_char('"')
  for character in value.to_array() {
    match character {
      '"' => output.write_string("\\\"")
      '\\' => output.write_string("\\\\")
      '\n' => output.write_string("\\n")
      '\r' => output.write_string("\\r")
      '\t' => output.write_string("\\t")
      '\u{0008}' => output.write_string("\\b")
      '\u{000c}' => output.write_string("\\f")
      _ => {
        let code = character.to_int()
        if code < 0x20 {
          output.write_string("\\u00")
          output.write_char(json_hex_digit((code >> 4) & 15))
          output.write_char(json_hex_digit(code & 15))
        } else {
          output.write_char(character)
        }
      }
    }
  }
  output.write_char('"')
  output.to_string()
}

///|
fn optional_json_string(value : String?) -> String {
  match value {
    Some(text) => json_string(text)
    None => "null"
  }
}

///|
fn optional_json_integer(value : Int32?) -> String {
  match value {
    Some(number) => number.to_string()
    None => "null"
  }
}

///|
fn image_info_json(info : ImageInfo?) -> String {
  match info {
    Some(image) =>
      "{\"width\":" +
      image.width.to_string() +
      ",\"height\":" +
      image.height.to_string() +
      ",\"luminance\":" +
      image.luminance.to_string() +
      ",\"red\":" +
      image.red.to_string() +
      ",\"green\":" +
      image.green.to_string() +
      ",\"blue\":" +
      image.blue.to_string() +
      "}"
    None => "null"
  }
}

///|
/// Export the full decision table as a UTF-8 JSON array. This is a report
/// artifact; it is not an approval file and cannot be passed to `apply`.
pub fn review_rows_json(rows : Array[ReviewRow]) -> String {
  let output = StringBuilder()
  output.write_char('[')
  for index = 0; index < rows.length(); index = index + 1 {
    if index > 0 {
      output.write_char(',')
    }
    let row = rows[index]
    output.write_string("{\"path\":")
    output.write_string(json_string(row.path))
    output.write_string(",\"name\":")
    output.write_string(json_string(row.name))
    output.write_string(",\"digest\":")
    output.write_string(json_string(row.digest))
    output.write_string(",\"kind\":")
    output.write_string(json_string(row.kind.code()))
    output.write_string(",\"matchPath\":")
    output.write_string(optional_json_string(row.match_path))
    output.write_string(",\"similarityDistance\":")
    output.write_string(optional_json_integer(row.similarity_distance))
    output.write_string(",\"destination\":")
    output.write_string(optional_json_string(row.destination))
    output.write_string(",\"size\":")
    output.write_string(row.size.to_string())
    output.write_string(",\"imageInfo\":")
    output.write_string(image_info_json(row.image_info))
    output.write_char('}')
  }
  output.write_char(']')
  output.to_string()
}

///|
fn starts_formula(value : String) -> Bool {
  let characters = value.to_array()
  let mut index = 0
  while index < characters.length() &&
        (
          characters[index] == ' ' ||
          characters[index] == '\t' ||
          characters[index] == '\r' ||
          characters[index] == '\n'
        ) {
    index = index + 1
  }
  if index >= characters.length() {
    return false
  }
  match characters[index] {
    '=' | '+' | '-' | '@' => true
    _ => false
  }
}

///|
/// Quote every CSV field so commas, quotes, line breaks and spreadsheet text
/// are preserved as data. Formula-like text receives a leading apostrophe for
/// safer opening in spreadsheet software; JSON remains the exact-value export.
pub fn csv_field(value : String) -> String {
  let output = StringBuilder()
  output.write_char('"')
  if starts_formula(value) {
    output.write_char('\'')
  }
  for character in value.to_array() {
    if character == '"' {
      output.write_string("\"\"")
    } else {
      output.write_char(character)
    }
  }
  output.write_char('"')
  output.to_string()
}

///|
fn optional_csv(value : String?) -> String {
  match value {
    Some(text) => text
    None => ""
  }
}

///|
fn row_csv(row : ReviewRow) -> String {
  let fields = [
    row.path,
    row.name,
    row.digest,
    row.kind.code(),
    optional_csv(row.match_path),
    optional_csv(row.similarity_distance.map(x => x.to_string())),
    optional_csv(row.destination),
    row.size.to_string(),
    optional_csv(row.image_info.map(x => image_info_label(x))),
  ]
  let output = StringBuilder()
  for index = 0; index < fields.length(); index = index + 1 {
    if index > 0 {
      output.write_char(',')
    }
    output.write_string(csv_field(fields[index]))
  }
  output.to_string()
}

///|
/// Export decisions as RFC-style quoted CSV for spreadsheet review.
pub fn review_rows_csv(rows : Array[ReviewRow]) -> String {
  let output = StringBuilder()
  output.write_string(
    "path,name,sha256,kind,match_path,similarity_distance,destination,size_bytes,image_info\r\n",
  )
  for row in rows {
    output.write_string(row_csv(row))
    output.write_string("\r\n")
  }
  output.to_string()
}

///|
/// Export a concise scan inventory as JSON for scripts and audit tools.
pub fn inventory_json(
  summary : InventorySummary,
  extensions : Array[ExtensionStats],
  size_bands : Array[SizeBandStats],
) -> String {
  let output = StringBuilder()
  output.write_string("{\"total\":")
  output.write_string(summary.total.to_string())
  output.write_string(",\"readable\":")
  output.write_string(summary.readable.to_string())
  output.write_string(",\"unreadable\":")
  output.write_string(summary.unreadable.to_string())
  output.write_string(",\"bytes\":")
  output.write_string(summary.bytes.to_string())
  output.write_string(",\"averageBytes\":")
  output.write_string(summary.average_size.to_string())
  output.write_string(",\"dimensions\":{\"landscape\":")
  output.write_string(summary.landscape.to_string())
  output.write_string(",\"portrait\":")
  output.write_string(summary.portrait.to_string())
  output.write_string(",\"square\":")
  output.write_string(summary.square.to_string())
  output.write_string(",\"unknown\":")
  output.write_string(summary.unknown_dimensions.to_string())
  output.write_string("},\"pixels\":")
  output.write_string(summary.pixels.to_string())
  output.write_string(",\"duplicateFileGroups\":")
  output.write_string(summary.duplicate_file_groups.to_string())
  output.write_string(",\"duplicateExtraFiles\":")
  output.write_string(summary.duplicate_files.to_string())
  output.write_string(",\"extensions\":[")
  for index = 0; index < extensions.length(); index = index + 1 {
    if index > 0 {
      output.write_char(',')
    }
    let item = extensions[index]
    output.write_string("{\"extension\":")
    output.write_string(json_string(item.extension))
    output.write_string(",\"count\":")
    output.write_string(item.count.to_string())
    output.write_string(",\"readable\":")
    output.write_string(item.readable.to_string())
    output.write_string(",\"unreadable\":")
    output.write_string(item.unreadable.to_string())
    output.write_string(",\"bytes\":")
    output.write_string(item.bytes.to_string())
    output.write_char('}')
  }
  output.write_string("],\"sizeBands\":[")
  for index = 0; index < size_bands.length(); index = index + 1 {
    if index > 0 {
      output.write_char(',')
    }
    let band = size_bands[index]
    output.write_string("{\"label\":")
    output.write_string(json_string(band.band.label()))
    output.write_string(",\"count\":")
    output.write_string(band.count.to_string())
    output.write_string(",\"bytes\":")
    output.write_string(band.bytes.to_string())
    output.write_char('}')
  }
  output.write_string("]}")
  output.to_string()
}

///|
/// Export aggregate extension totals as a spreadsheet-friendly CSV.
pub fn extension_summary_csv(items : Array[ExtensionStats]) -> String {
  let output = StringBuilder()
  output.write_string("extension,count,readable,unreadable,bytes\r\n")
  for item in items {
    output.write_string(csv_field(item.extension))
    output.write_char(',')
    output.write_string(item.count.to_string())
    output.write_char(',')
    output.write_string(item.readable.to_string())
    output.write_char(',')
    output.write_string(item.unreadable.to_string())
    output.write_char(',')
    output.write_string(item.bytes.to_string())
    output.write_string("\r\n")
  }
  output.to_string()
}
