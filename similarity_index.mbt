///|
/// One possible visual match found by the Hamming-distance index.
pub(all) struct SimilarityHit {
  path : String
  name : String
  digest : String
  distance : Int32
}

///|
/// Segmented signature index. A signature within the configured Hamming limit
/// must share at least one complete segment, so each lookup examines only
/// buckets that can contain a qualifying candidate and verifies the full
/// distance before returning it.
pub struct SimilarityIndex {
  max_distance : Int32
  entries : Array[Photo]
  buckets64 : Array[Map[String, Array[Int32]]]
  buckets176 : Array[Map[String, Array[Int32]]]
}

///|
fn new_buckets(
  width : Int32,
  max_distance : Int32,
) -> Array[Map[String, Array[Int32]]] {
  let parts = (max_distance + 1).min(width).max(1)
  let buckets : Array[Map[String, Array[Int32]]] = []
  for index = 0; index < parts; index = index + 1 {
    buckets.push(Map([]))
  }
  buckets
}

///|
/// Create an index whose guarantee applies up to `max_distance` differing bits.
/// The supported signature widths are 64 and 176 bits.
pub fn new_similarity_index(max_distance : Int32) -> SimilarityIndex {
  let distance = max_distance.max(0).min(176)
  {
    max_distance: distance,
    entries: [],
    buckets64: new_buckets(64, distance),
    buckets176: new_buckets(176, distance),
  }
}

///|
fn signature_width(signature : String) -> Int32 {
  if signature.length() == 64 || signature.length() == 176 {
    signature.length()
  } else {
    0
  }
}

///|
fn segment_key(signature : String, part : Int32, parts : Int32) -> String {
  let width = signature.length()
  let start = width * part / parts
  let end = width * (part + 1) / parts
  let builder = StringBuilder()
  for index = start; index < end; index = index + 1 {
    builder.write_char(signature[index].unsafe_to_char())
  }
  builder.to_string()
}

///|
fn add_to_buckets(
  buckets : Array[Map[String, Array[Int32]]],
  signature : String,
  entry_index : Int32,
) -> Unit {
  let parts = buckets.length()
  for part = 0; part < parts; part = part + 1 {
    let key = segment_key(signature, part, parts)
    match buckets[part].get(key) {
      Some(indices) => indices.push(entry_index)
      None => buckets[part].set(key, [entry_index])
    }
  }
}

///|
/// Add a decodable photo to the index. Unsupported or absent signatures are
/// ignored and cannot be returned as visual candidates.
pub fn SimilarityIndex::add(self : SimilarityIndex, photo : Photo) -> Unit {
  match photo.fingerprint {
    Some(signature) => {
      let width = signature_width(signature)
      if width == 64 {
        let index = self.entries.length()
        self.entries.push(photo)
        add_to_buckets(self.buckets64, signature, index)
      } else if width == 176 {
        let index = self.entries.length()
        self.entries.push(photo)
        add_to_buckets(self.buckets176, signature, index)
      }
    }
    None => ()
  }
}

///|
fn collect_bucket_candidates(
  buckets : Array[Map[String, Array[Int32]]],
  signature : String,
  seen : Map[Int32, Bool],
  result : Array[Int32],
) -> Unit {
  let parts = buckets.length()
  for part = 0; part < parts; part = part + 1 {
    let key = segment_key(signature, part, parts)
    match buckets[part].get(key) {
      Some(indices) =>
        for index in indices {
          if seen.get(index) is None {
            seen.set(index, true)
            result.push(index)
          }
        }
      None => ()
    }
  }
}

///|
fn hit_precedes(left : SimilarityHit, right : SimilarityHit) -> Bool {
  left.distance < right.distance ||
  (left.distance == right.distance && left.path.lexical_compare(right.path) < 0)
}

///|
/// Return all candidates at or below a requested distance, ordered by distance
/// and then path. Results do not claim that files depict the same scene.
pub fn SimilarityIndex::search(
  self : SimilarityIndex,
  signature : String,
  limit : Int32,
) -> Array[SimilarityHit] {
  let width = signature_width(signature)
  if width == 0 || limit < 0 {
    return []
  }
  let effective_limit = limit.min(self.max_distance).min(width)
  let indices : Array[Int32] = []
  if effective_limit >= width {
    for index = 0; index < self.entries.length(); index = index + 1 {
      let photo = self.entries[index]
      if photo.fingerprint is Some(candidate) && candidate.length() == width {
        indices.push(index)
      }
    }
  } else {
    let seen : Map[Int32, Bool] = Map([])
    if width == 64 {
      collect_bucket_candidates(self.buckets64, signature, seen, indices)
    } else {
      collect_bucket_candidates(self.buckets176, signature, seen, indices)
    }
  }
  let hits : Array[SimilarityHit] = []
  for index in indices {
    let photo = self.entries[index]
    match photo.fingerprint {
      Some(candidate) => {
        let distance = hamming_distance(signature, candidate)
        if distance <= effective_limit {
          hits.push({
            path: photo.path,
            name: photo.name,
            digest: photo.digest,
            distance,
          })
        }
      }
      None => ()
    }
  }
  hits.sort_by((left, right) => {
    if hit_precedes(left, right) {
      -1
    } else if hit_precedes(right, left) {
      1
    } else {
      0
    }
  })
  hits
}

///|
/// Return the closest qualifying match. Equal distances resolve by path so
/// shuffled input order cannot change the selected reference.
pub fn SimilarityIndex::nearest(
  self : SimilarityIndex,
  signature : String,
  limit : Int32,
) -> SimilarityHit? {
  let hits = self.search(signature, limit)
  if hits.length() == 0 {
    None
  } else {
    Some(hits[0])
  }
}

///|
/// Number of decodable photos currently indexed.
pub fn SimilarityIndex::count(self : SimilarityIndex) -> Int32 {
  self.entries.length()
}

///|
/// Largest distance for which this index guarantees candidate recall.
pub fn SimilarityIndex::capacity(self : SimilarityIndex) -> Int32 {
  self.max_distance
}

///|
/// Count every qualifying unordered photo pair in an already-created index.
/// Each pair is returned once, in stable path order.
pub fn SimilarityIndex::all_pairs(
  self : SimilarityIndex,
  limit : Int32,
) -> Array[(String, String, Int32)] {
  let pairs : Array[(String, String, Int32)] = []
  let max_limit = limit.min(self.max_distance)
  for left_index = 0
      left_index < self.entries.length()
      left_index = left_index + 1 {
    let left = self.entries[left_index]
    match left.fingerprint {
      Some(signature) =>
        for hit in self.search(signature, max_limit) {
          if left.path.lexical_compare(hit.path) < 0 {
            pairs.push((left.path, hit.path, hit.distance))
          }
        }
      None => ()
    }
  }
  pairs.sort_by((left, right) => {
    let first = left.0.lexical_compare(right.0)
    if first != 0 {
      first
    } else {
      left.1.lexical_compare(right.1)
    }
  })
  pairs
}
