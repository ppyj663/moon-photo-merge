///|
test "default query returns path-sorted first page" {
  let rows = [
    test_row("z/third.jpg", New, 30, destination=Some("third.jpg")),
    test_row(
      "a/first.jpg",
      Similar,
      20,
      destination=Some("first.jpg"),
      distance=Some(3),
    ),
    test_row("b/second.jpg", Conflict, 10, destination=Some("second.jpg")),
  ]
  let query = default_review_query()
  let page = query_review_rows(rows, query)
  assert_eq(page.rows.length(), 3)
  assert_eq(page.rows[0].path, "a/first.jpg")
  assert_eq(page.rows[1].path, "b/second.jpg")
  assert_eq(page.rows[2].path, "z/third.jpg")
  assert_eq(page.total_matches, 3)
  assert_eq(page.page_count, 1)
  assert_true(!page.has_previous)
  assert_true(!page.has_next)
}

///|
test "text search is trimmed case insensitive and covers paths and category labels" {
  let rows = [
    test_row(
      "incoming/Travel/Beach.JPG",
      New,
      100,
      destination=Some("Beach.JPG"),
    ),
    test_row(
      "incoming/Portrait.png",
      Similar,
      200,
      destination=Some("Portrait.png"),
      distance=Some(1),
    ),
    test_row("incoming/Broken.jpg", Unreadable, 50),
  ]
  let path_query : ReviewQuery = {
    text: "  TRAVEL/beach  ",
    kind: None,
    minimum_size: None,
    maximum_size: None,
    sort: PathAscending,
    offset: 0,
    page_size: 50,
  }
  assert_eq(query_review_rows(rows, path_query).total_matches, 1)
  let label_query : ReviewQuery = {
    text: "疑似相似",
    kind: None,
    minimum_size: None,
    maximum_size: None,
    sort: PathAscending,
    offset: 0,
    page_size: 50,
  }
  assert_true(query_review_rows(rows, label_query).rows[0].kind == Similar)
}

///|
test "kind and inclusive size filters combine" {
  let rows = [
    test_row("a.jpg", New, 100, destination=Some("a.jpg")),
    test_row("b.jpg", New, 200, destination=Some("b.jpg")),
    test_row("c.jpg", Similar, 150, destination=Some("c.jpg"), distance=Some(3)),
  ]
  let query : ReviewQuery = {
    text: "",
    kind: Some(New),
    minimum_size: Some(100),
    maximum_size: Some(100),
    sort: PathAscending,
    offset: 0,
    page_size: 20,
  }
  let page = query_review_rows(rows, query)
  assert_eq(page.total_matches, 1)
  assert_eq(page.rows[0].path, "a.jpg")
}

///|
test "inverted size range and negative range do not wrap around" {
  let rows = [test_row("a.jpg", New, 10)]
  let inverted : ReviewQuery = {
    text: "",
    kind: None,
    minimum_size: Some(20),
    maximum_size: Some(10),
    sort: PathAscending,
    offset: 0,
    page_size: 10,
  }
  assert_eq(query_review_rows(rows, inverted).total_matches, 0)
  let negative : ReviewQuery = {
    text: "",
    kind: None,
    minimum_size: Some(-10),
    maximum_size: Some(10),
    sort: PathAscending,
    offset: 0,
    page_size: 10,
  }
  assert_eq(query_review_rows(rows, negative).total_matches, 1)
}

///|
test "pagination clamps offsets and reports previous and next pages" {
  let rows = [
    test_row("a.jpg", New, 1),
    test_row("b.jpg", New, 2),
    test_row("c.jpg", New, 3),
    test_row("d.jpg", New, 4),
    test_row("e.jpg", New, 5),
  ]
  let query : ReviewQuery = {
    text: "",
    kind: None,
    minimum_size: None,
    maximum_size: None,
    sort: PathAscending,
    offset: 2,
    page_size: 2,
  }
  let page = query_review_rows(rows, query)
  assert_eq(page.rows.length(), 2)
  assert_eq(page.rows[0].path, "c.jpg")
  assert_eq(page.rows[1].path, "d.jpg")
  assert_eq(page.total_matches, 5)
  assert_eq(page.page_count, 3)
  assert_true(page.has_previous)
  assert_true(page.has_next)
  let beyond = query_review_rows(rows, test_query(PathAscending, 90, 2))
  assert_eq(beyond.rows.length(), 0)
  assert_eq(beyond.offset, 5)
  assert_true(!beyond.has_next)
  assert_eq(review_page_start(3, 2), 4)
  assert_eq(review_page_number(4, 2), 3)
}

///|
test "page size is bounded to a safe range" {
  let rows = [test_row("a.jpg", New, 1)]
  let zero = query_review_rows(rows, test_query(PathAscending, 0, 0))
  assert_eq(zero.page_size, 1)
  let huge = query_review_rows(rows, test_query(PathAscending, 0, 10000))
  assert_eq(huge.page_size, 500)
}

///|
test "sort modes use stable tie breakers" {
  let rows = [
    test_row("z.jpg", Similar, 300, distance=Some(2)),
    test_row("b.jpg", Similar, 900, distance=Some(1)),
    test_row("a.jpg", Similar, 900, distance=Some(1)),
    test_row("c.jpg", New, 500),
  ]
  let by_distance = query_review_rows(
    rows,
    test_query(SimilarityAscending, 0, 100),
  )
  assert_eq(by_distance.rows[0].path, "a.jpg")
  assert_eq(by_distance.rows[1].path, "b.jpg")
  let by_size = query_review_rows(rows, test_query(SizeDescending, 0, 100))
  assert_eq(by_size.rows[0].path, "a.jpg")
  assert_eq(by_size.rows[1].path, "b.jpg")
  let by_kind = query_review_rows(rows, test_query(CategoryThenPath, 0, 100))
  assert_true(by_kind.rows[0].kind == New)
  assert_eq(by_kind.rows[0].path, "c.jpg")
}

///|
test "empty page uses zero pages and clamped nonnegative offset" {
  let query = test_query(PathAscending, -5, 100)
  let page = query_review_rows([], query)
  assert_eq(page.offset, 0)
  assert_eq(page.page_count, 0)
  assert_eq(page.rows.length(), 0)
  assert_true(!page.has_previous)
  assert_true(!page.has_next)
}
