///|
test "exact duplicate beats filename conflict" {
  let existing : Array[@photo_merge.Photo] = [
    {
      path: "old/a.jpg",
      name: "a.jpg",
      digest: "same",
      fingerprint: Some("0".repeat(64)),
      size: 10,
    },
  ]
  let incoming : Array[@photo_merge.Photo] = [
    {
      path: "new/a.jpg",
      name: "a.jpg",
      digest: "same",
      fingerprint: Some("0".repeat(64)),
      size: 10,
    },
  ]
  let rows = @photo_merge.build_plan(existing, incoming)
  assert_true(rows[0].kind == @photo_merge.Kind::Exact)
  assert_eq(rows[0].destination, None)
}

///|
test "same name with different bytes receives a safe name" {
  let existing : Array[@photo_merge.Photo] = [
    {
      path: "old/a.jpg",
      name: "a.jpg",
      digest: "old",
      fingerprint: Some("0".repeat(64)),
      size: 10,
    },
  ]
  let incoming : Array[@photo_merge.Photo] = [
    {
      path: "new/a.jpg",
      name: "a.jpg",
      digest: "new",
      fingerprint: Some("1".repeat(64)),
      size: 20,
    },
  ]
  let rows = @photo_merge.build_plan(existing, incoming)
  assert_true(rows[0].kind == @photo_merge.Kind::Conflict)
  assert_eq(rows[0].destination, Some("a-import-1.jpg"))
}

///|
test "visually close files need review" {
  let existing : Array[@photo_merge.Photo] = [
    {
      path: "old/a.png",
      name: "a.png",
      digest: "one",
      fingerprint: Some("0".repeat(64)),
      size: 10,
    },
  ]
  let incoming : Array[@photo_merge.Photo] = [
    {
      path: "new/b.png",
      name: "b.png",
      digest: "two",
      fingerprint: Some("0".repeat(63) + "1"),
      size: 20,
    },
  ]
  let rows = @photo_merge.build_plan(existing, incoming)
  assert_true(rows[0].kind == @photo_merge.Kind::Similar)
  assert_eq(rows[0].match_path, Some("old/a.png"))
}

///|
test "undecodable images are not planned for copying" {
  let incoming : Array[@photo_merge.Photo] = [
    {
      path: "new/broken.jpg",
      name: "broken.jpg",
      digest: "x",
      fingerprint: None,
      size: 3,
    },
  ]
  let rows = @photo_merge.build_plan([], incoming)
  assert_true(rows[0].kind == @photo_merge.Kind::Unreadable)
  assert_eq(rows[0].destination, None)
}

///|
test "identical unreadable bytes never become an exact duplicate" {
  let existing : Array[@photo_merge.Photo] = [
    {
      path: "library/broken.jpg",
      name: "broken.jpg",
      digest: "bad",
      fingerprint: None,
      size: 3,
    },
  ]
  let incoming : Array[@photo_merge.Photo] = [
    {
      path: "incoming/broken.jpg",
      name: "broken.jpg",
      digest: "bad",
      fingerprint: None,
      size: 3,
    },
  ]
  let rows = @photo_merge.build_plan(existing, incoming)
  assert_true(rows[0].kind == @photo_merge.Kind::Unreadable)
  assert_eq(rows[0].destination, None)
}

///|
test "two different incoming files with the same basename get distinct targets" {
  let incoming : Array[@photo_merge.Photo] = [
    {
      path: "incoming/a/photo.jpg",
      name: "photo.jpg",
      digest: "first",
      fingerprint: Some("0".repeat(64)),
      size: 10,
    },
    {
      path: "incoming/b/photo.jpg",
      name: "photo.jpg",
      digest: "second",
      fingerprint: Some("1".repeat(64)),
      size: 10,
    },
  ]
  let rows = @photo_merge.build_plan([], incoming)
  assert_eq(rows[0].destination, Some("photo.jpg"))
  assert_true(rows[1].kind == @photo_merge.Kind::Conflict)
  assert_eq(rows[1].destination, Some("photo-import-1.jpg"))
}
