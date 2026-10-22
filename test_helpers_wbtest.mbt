///|
fn test_photo(
  path : String,
  name : String,
  digest : String,
  fingerprint : String?,
  size : Int32,
  image_info~ : ImageInfo? = None,
) -> Photo {
  { path, name, digest, fingerprint, size, image_info, }
}

///|
fn test_row(
  path : String,
  kind : Kind,
  size : Int32,
  destination~ : String? = None,
  distance~ : Int32? = None,
  match_path~ : String? = None,
  image_info~ : ImageInfo? = None,
) -> ReviewRow {
  {
    path,
    name: path,
    digest: "digest-" + path,
    kind,
    match_path,
    similarity_distance: distance,
    destination,
    size,
    image_info,
  }
}

///|
fn signature_with_ones(width : Int32, positions : Array[Int32]) -> String {
  let selected : Map[Int32, Bool] = Map([])
  for position in positions {
    selected.set(position, true)
  }
  let output = StringBuilder()
  for index = 0; index < width; index = index + 1 {
    output.write_char(if selected.get(index) is Some(_) { '1' } else { '0' })
  }
  output.to_string()
}

///|
fn test_query(
  sort : ReviewSort,
  offset : Int32,
  page_size : Int32,
) -> ReviewQuery {
  {
    text: "",
    kind: None,
    minimum_size: None,
    maximum_size: None,
    sort,
    offset,
    page_size,
  }
}
