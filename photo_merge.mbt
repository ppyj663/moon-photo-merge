///|
/// Basic decoded-image facts used for inventory and human review.
pub(all) struct ImageInfo {
  width : Int32
  height : Int32
  luminance : Int32
  red : Int32
  green : Int32
  blue : Int32
}

///|
/// Facts about one regular JPEG/PNG file. Missing fingerprint means decoding failed.
pub(all) struct Photo {
  path : String
  name : String
  digest : String
  fingerprint : String?
  size : Int32
  image_info : ImageInfo?
}

///|
pub(all) enum Kind {
  Exact
  Similar
  Conflict
  New
  Unreadable
} derive(Eq)

///|
pub extend Kind with Eq::{not_equal, equal}

///|
pub(all) struct ReviewRow {
  path : String
  name : String
  digest : String
  kind : Kind
  match_path : String?
  similarity_distance : Int32?
  destination : String?
  size : Int32
  image_info : ImageInfo?
}

///|
pub fn Kind::label(self : Kind) -> String {
  match self {
    Exact => "完全重复"
    Similar => "疑似相似"
    Conflict => "同名冲突"
    New => "可新增"
    Unreadable => "图片无法解码"
  }
}

///|
pub fn Kind::code(self : Kind) -> String {
  match self {
    Exact => "exact"
    Similar => "similar"
    Conflict => "conflict"
    New => "new"
    Unreadable => "unreadable"
  }
}

///|
pub fn hamming_distance(a : String, b : String) -> Int32 {
  if a.length() != b.length() || (a.length() != 64 && a.length() != 176) {
    return 177
  }
  let mut count = 0
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      count = count + 1
    }
  }
  count
}

///|
fn unique_name(name : String, reserved : Map[String, String]) -> String {
  if reserved.get(name.to_lower()) is None {
    return name
  }
  let (stem, ext) = match name.rev_split_once(".") {
    Some((head, tail)) if head.length() > 0 && tail.length() > 0 =>
      (head.to_owned(), "." + tail.to_owned())
    Some((head, _)) if head.length() > 0 => (head.to_owned(), "")
    _ => (name, "")
  }
  for number = 1; number <= 100000; number = number + 1 {
    let candidate = "\{stem}-import-\{number}\{ext}"
    if reserved.get(candidate.to_lower()) is None {
      return candidate
    }
  }
  name + "-import-overflow"
}

///|
/// Similarity is a review hint; only identical bytes are auto-skipped.
pub fn build_plan(
  existing : Array[Photo],
  incoming : Array[Photo],
  similar_limit~ : Int32 = 5,
) -> Array[ReviewRow] {
  let effective_limit = similar_limit.max(0).min(176)
  let digests : Map[String, String] = Map([])
  let names : Map[String, String] = Map([])
  let index = new_similarity_index(effective_limit)
  for photo in existing {
    if names.get(photo.name.to_lower()) is None {
      names.set(photo.name.to_lower(), photo.path)
    }
    if photo.fingerprint is Some(_) {
      if digests.get(photo.digest) is None {
        digests.set(photo.digest, photo.path)
      }
      index.add(photo)
    }
  }
  let rows : Array[ReviewRow] = []
  for photo in incoming {
    if photo.fingerprint is None {
      rows.push({
        path: photo.path,
        name: photo.name,
        digest: photo.digest,
        kind: Unreadable,
        match_path: None,
        similarity_distance: None,
        destination: None,
        size: photo.size,
        image_info: photo.image_info,
      })
      continue
    }
    match digests.get(photo.digest) {
      Some(first) => {
        rows.push({
          path: photo.path,
          name: photo.name,
          digest: photo.digest,
          kind: Exact,
          match_path: Some(first),
          similarity_distance: None,
          destination: None,
          size: photo.size,
          image_info: photo.image_info,
        })
        continue
      }
      None => ()
    }
    let conflicting = names.get(photo.name.to_lower())
    let best = match photo.fingerprint {
      Some(fingerprint) => index.nearest(fingerprint, effective_limit)
      None => None
    }
    let closest = match best {
      Some(hit) => Some(hit.path)
      None => None
    }
    let closest_distance = match best {
      Some(hit) => hit.distance
      None => 177
    }
    let kind = if photo.fingerprint is None {
      Unreadable
    } else if conflicting is Some(_) {
      Conflict
    } else if closest_distance <= effective_limit {
      Similar
    } else {
      New
    }
    let match_path = match kind {
      Conflict => conflicting
      Similar => closest
      _ => None
    }
    let destination = match kind {
      Unreadable => None
      _ => Some(unique_name(photo.name, names))
    }
    rows.push({
      path: photo.path,
      name: photo.name,
      digest: photo.digest,
      kind,
      match_path,
      similarity_distance: if kind == Similar {
        Some(closest_distance)
      } else {
        None
      },
      destination,
      size: photo.size,
      image_info: photo.image_info,
    })
    if photo.fingerprint is Some(_) {
      digests.set(photo.digest, photo.path)
      index.add(photo)
      match destination {
        Some(target) => names.set(target.to_lower(), photo.path)
        None => ()
      }
    }
  }
  rows
}
