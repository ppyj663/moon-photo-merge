///|
test "similarity groups connect direct pairs and keep transitive meaning explicit" {
  let photos = [
    test_photo("c.jpg", "c.jpg", "c", Some(signature_with_ones(64, [0, 1])), 1),
    test_photo("a.jpg", "a.jpg", "a", Some("0".repeat(64)), 1),
    test_photo("b.jpg", "b.jpg", "b", Some(signature_with_ones(64, [0])), 1),
    test_photo("far-away.jpg", "far-away.jpg", "x", Some("1".repeat(64)), 1),
  ]
  let groups = similarity_groups(photos, 1)
  assert_eq(groups.length(), 1)
  assert_eq(groups[0].paths, ["a.jpg", "b.jpg", "c.jpg"])
  assert_eq(groups[0].pair_count, 2)
  assert_eq(groups[0].minimum_distance, 1)
  assert_eq(groups[0].maximum_distance, 1)
}

///|
test "similarity group does not imply exact duplicate bytes" {
  let photos = [
    test_photo("a.jpg", "a.jpg", "bytes-a", Some("0".repeat(176)), 1),
    test_photo("b.jpg", "b.jpg", "bytes-b", Some("0".repeat(176)), 1),
  ]
  let groups = similarity_groups(photos, 0)
  assert_eq(groups.length(), 1)
  assert_eq(groups[0].pair_count, 1)
  assert_eq(photos[0].digest == photos[1].digest, false)
}

///|
test "separate connected components are ordered by their first path" {
  let photos = [
    test_photo("long-name-z.jpg", "z.jpg", "z", Some("0".repeat(64)), 1),
    test_photo("a.jpg", "a.jpg", "a", Some("0".repeat(63) + "1"), 1),
    test_photo("z.jpg", "z.jpg", "z2", Some("1".repeat(64)), 1),
    test_photo("b.jpg", "b.jpg", "b", Some("1".repeat(63) + "0"), 1),
  ]
  let groups = similarity_groups(photos, 1)
  assert_eq(groups.length(), 2)
  assert_eq(groups[0].paths, ["a.jpg", "long-name-z.jpg"])
  assert_eq(groups[1].paths, ["b.jpg", "z.jpg"])
}

///|
test "group summaries count unique members and edges" {
  let photos = [
    test_photo("a.jpg", "a.jpg", "a", Some("0".repeat(64)), 1),
    test_photo("b.jpg", "b.jpg", "b", Some(signature_with_ones(64, [0])), 1),
    test_photo("c.jpg", "c.jpg", "c", Some(signature_with_ones(64, [0, 1])), 1),
  ]
  let groups = similarity_groups(photos, 1)
  let summary = similarity_groups_summary(groups)
  assert_eq(summary.groups, 1)
  assert_eq(summary.members, 3)
  assert_eq(summary.pairs, 2)
  assert_eq(summary.largest_group, 3)
}

///|
test "path lookup finds only connected review groups" {
  let photos = [
    test_photo("a.jpg", "a.jpg", "a", Some("0".repeat(64)), 1),
    test_photo("b.jpg", "b.jpg", "b", Some("0".repeat(63) + "1"), 1),
    test_photo("far.jpg", "far.jpg", "f", Some("1".repeat(64)), 1),
  ]
  let groups = similarity_groups(photos, 1)
  assert_eq(
    find_similarity_group(groups, "a.jpg").map(x => x.paths.length()),
    Some(2),
  )
  assert_true(find_similarity_group(groups, "far.jpg") is None)
}

///|
test "group JSON escapes paths and preserves direct edge counts" {
  let photos = [
    test_photo("in/a\".jpg", "a.jpg", "a", Some("0".repeat(64)), 1),
    test_photo("in/b.jpg", "b.jpg", "b", Some("0".repeat(63) + "1"), 1),
  ]
  let json = similarity_groups_json(similarity_groups(photos, 1))
  assert_true(json.contains("in/a\\\".jpg"))
  assert_true(json.contains("\"pairCount\":1"))
  assert_true(json.contains("\"minimumDistance\":1"))
  assert_true(json.contains("\"maximumDistance\":1"))
}

///|
test "direct pair CSV quotes paths and keeps one row per edge" {
  let pairs : Array[(String, String, Int32)] = [("a,one.jpg", "b\"two.jpg", 3)]
  let csv = similarity_pairs_csv(pairs)
  let quote = "\""
  let expected = quote +
    "a,one.jpg" +
    quote +
    "," +
    quote +
    "b" +
    quote +
    quote +
    "two.jpg" +
    quote +
    ",3"
  assert_true(csv.contains(expected))
}

///|
test "no qualifying edges yields empty groups and a zero summary" {
  let photos = [
    test_photo("a.jpg", "a.jpg", "a", Some("0".repeat(64)), 1),
    test_photo("b.jpg", "b.jpg", "b", Some("1".repeat(64)), 1),
  ]
  let groups = similarity_groups(photos, 0)
  let summary = similarity_groups_summary(groups)
  assert_eq(groups.length(), 0)
  assert_eq(similarity_groups_json(groups), "[]")
  assert_eq(summary.members, 0)
  assert_eq(summary.pairs, 0)
  assert_eq(summary.largest_group, 0)
}
