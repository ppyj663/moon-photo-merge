///|
test "segmented index finds matches spread across every fingerprint region" {
  let base = "0".repeat(64)
  let candidate = signature_with_ones(64, [0, 13, 27, 41])
  let index = new_similarity_index(4)
  index.add(test_photo("library/base.jpg", "base.jpg", "a", Some(base), 10))
  let hits = index.search(candidate, 4)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].path, "library/base.jpg")
  assert_eq(hits[0].distance, 4)
}

///|
test "index verifies bucket candidates with the complete Hamming distance" {
  let index = new_similarity_index(5)
  index.add(
    test_photo("library/one.jpg", "one.jpg", "one", Some("0".repeat(64)), 1),
  )
  index.add(
    test_photo(
      "library/too-far.jpg",
      "too-far.jpg",
      "far",
      Some(signature_with_ones(64, [0, 10, 20, 30, 40, 50])),
      2,
    ),
  )
  let hits = index.search("0".repeat(64), 2)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].distance, 0)
}

///|
test "index supports both documented signature widths and ignores malformed values" {
  let index = new_similarity_index(3)
  index.add(
    test_photo("library/64.jpg", "64.jpg", "a", Some("0".repeat(64)), 1),
  )
  index.add(
    test_photo("library/176.jpg", "176.jpg", "b", Some("0".repeat(176)), 1),
  )
  index.add(test_photo("library/bad.jpg", "bad.jpg", "c", Some("bad"), 1))
  index.add(test_photo("library/none.jpg", "none.jpg", "d", None, 1))
  assert_eq(index.count(), 2)
  assert_eq(index.search("0".repeat(64), 3).length(), 1)
  assert_eq(index.search("0".repeat(176), 3).length(), 1)
  assert_eq(index.search("bad", 3).length(), 0)
}

///|
test "nearest result is stable when equal-distance candidates are added in another order" {
  let first = signature_with_ones(64, [0])
  let second = signature_with_ones(64, [1])
  let forward = new_similarity_index(2)
  forward.add(test_photo("z.jpg", "z.jpg", "z", Some(second), 1))
  forward.add(test_photo("a.jpg", "a.jpg", "a", Some(first), 1))
  let backward = new_similarity_index(2)
  backward.add(test_photo("a.jpg", "a.jpg", "a", Some(first), 1))
  backward.add(test_photo("z.jpg", "z.jpg", "z", Some(second), 1))
  assert_eq(forward.nearest("0".repeat(64), 2).map(x => x.path), Some("a.jpg"))
  assert_eq(backward.nearest("0".repeat(64), 2).map(x => x.path), Some("a.jpg"))
}

///|
test "similarity hits are sorted by distance then path" {
  let index = new_similarity_index(4)
  index.add(
    test_photo("z.jpg", "z.jpg", "z", Some(signature_with_ones(176, [0, 1])), 2),
  )
  index.add(
    test_photo("b.jpg", "b.jpg", "b", Some(signature_with_ones(176, [0])), 2),
  )
  index.add(
    test_photo("a.jpg", "a.jpg", "a", Some(signature_with_ones(176, [1])), 2),
  )
  let hits = index.search("0".repeat(176), 2)
  assert_eq(hits.length(), 3)
  assert_eq(hits[0].path, "a.jpg")
  assert_eq(hits[1].path, "b.jpg")
  assert_eq(hits[2].path, "z.jpg")
  assert_eq(hits[2].distance, 2)
}

///|
test "index capacity clamps invalid thresholds and search never exceeds the guarantee" {
  let none = new_similarity_index(-4)
  assert_eq(none.capacity(), 0)
  none.add(test_photo("a.jpg", "a.jpg", "a", Some("0".repeat(64)), 1))
  assert_eq(none.search("1".repeat(64), 10).length(), 0)
  let full = new_similarity_index(999)
  assert_eq(full.capacity(), 176)
  full.add(test_photo("a.jpg", "a.jpg", "a", Some("0".repeat(64)), 1))
  assert_eq(full.search("1".repeat(64), 64).length(), 1)
}

///|
test "pair enumeration returns each qualifying pair once" {
  let index = new_similarity_index(1)
  index.add(test_photo("c.jpg", "c.jpg", "c", Some("0".repeat(64)), 1))
  index.add(test_photo("a.jpg", "a.jpg", "a", Some("0".repeat(63) + "1"), 1))
  index.add(test_photo("far.jpg", "far.jpg", "far", Some("1".repeat(64)), 1))
  let pairs = index.all_pairs(1)
  assert_eq(pairs.length(), 1)
  assert_eq(pairs[0].0, "a.jpg")
  assert_eq(pairs[0].1, "c.jpg")
  assert_eq(pairs[0].2, 1)
}

///|
test "index returns all nearby candidates and supports tighter per-query limits" {
  let index = new_similarity_index(5)
  index.add(test_photo("one.jpg", "one.jpg", "one", Some("0".repeat(64)), 1))
  index.add(
    test_photo(
      "two.jpg",
      "two.jpg",
      "two",
      Some(signature_with_ones(64, [1, 2])),
      1,
    ),
  )
  index.add(
    test_photo(
      "three.jpg",
      "three.jpg",
      "three",
      Some(signature_with_ones(64, [1, 2, 3, 4])),
      1,
    ),
  )
  let all = index.search("0".repeat(64), 5)
  let exact = index.search("0".repeat(64), 0)
  assert_eq(all.length(), 3)
  assert_eq(exact.length(), 1)
  assert_eq(exact[0].distance, 0)
  assert_eq(index.search("0".repeat(64), -1).length(), 0)
}

///|
test "an indexed unreadable photo does not become a candidate" {
  let index = new_similarity_index(8)
  index.add(test_photo("bad.jpg", "bad.jpg", "bad", None, 3))
  assert_eq(index.count(), 0)
  assert_eq(index.search("0".repeat(64), 8).length(), 0)
}

///|
test "distance index maintains candidate recall for a generated deterministic set" {
  let signatures : Array[String] = []
  for seed = 0; seed < 96; seed = seed + 1 {
    let positions : Array[Int32] = []
    for bit = 0; bit < 176; bit = bit + 1 {
      let value = (bit * 17 + seed * 29 + bit * seed) % 31
      if value < 3 {
        positions.push(bit)
      }
    }
    signatures.push(signature_with_ones(176, positions))
  }
  let index = new_similarity_index(7)
  for i = 0; i < signatures.length(); i = i + 1 {
    index.add(
      test_photo(
        "p" + i.to_string() + ".jpg",
        "p" + i.to_string() + ".jpg",
        i.to_string(),
        Some(signatures[i]),
        1,
      ),
    )
  }
  for i = 0; i < signatures.length(); i = i + 1 {
    let expected = signatures
      .filter(signature => hamming_distance(signatures[i], signature) <= 7)
      .length()
    let actual = index.search(signatures[i], 7).length()
    assert_eq(actual, expected)
  }
}
